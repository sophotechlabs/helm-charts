# helm-charts — every gate CI runs, runnable locally with the same tools
# deps: mise (mise install), then `just deps` for the helm plugins

# A raw single-quoted string: just does not interpolate inside one, so the
# kubeconform placeholders survive verbatim.
kubeconform_schemas := 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
render_dir := justfile_directory() / 'dist/render'
kind_cluster := 'helm-charts'

# list recipes
default:
    @just --list

# everything CI runs, in the order that fails fastest
validate: fmt-check yaml workflows hygiene links commits lint schema docs unittest render secrets sast vulns
    @echo "✓ all client-side gates passed"

# install the helm plugins mise cannot manage
deps:
    #!/usr/bin/env bash
    set -euo pipefail
    if helm plugin list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx unittest; then
        echo "helm-unittest already installed"
        exit 0
    fi
    helm plugin install https://github.com/helm-unittest/helm-unittest --version "${HELM_UNITTEST_VERSION:-1.1.2}"

# ── charts ────────────────────────────────────────────────────────────────────

# helm lint every chart against every scenario it claims to support
# (linting bare defaults would only prove the schema rejects an empty hostname,
# which is the schema doing its job rather than the chart being sound)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for chart in charts/*/; do
        for values in "$chart"ci/*-values.yaml; do
            [ -f "$values" ] || continue
            echo "==> helm lint $chart $(basename "$values")"
            helm lint --strict "$chart" -f "$values"
        done
    done

# render every scenario into dist/render
render: _render kubeconform kube-linter

_render:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf {{ render_dir }}
    mkdir -p {{ render_dir }}
    count=0
    for chart in charts/*/; do
        name=$(basename "$chart")
        for values in "$chart"ci/*-values.yaml; do
            [ -f "$values" ] || continue
            scenario=$(basename "$values" -values.yaml)
            out="{{ render_dir }}/$name-$scenario.yaml"
            if ! helm template "$name" "$chart" --namespace ci -f "$values" > "$out"; then
                echo "FAIL  render $name/$scenario"
                exit 1
            fi
            count=$((count + 1))
        done
    done
    if [ "$count" -eq 0 ]; then
        echo "no scenarios found under test/render — that is a bug in the test layout, not a pass"
        exit 1
    fi
    echo "rendered $count scenarios"

# schema-validate every rendered scenario, CRDs included
kubeconform:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=({{ render_dir }}/*.yaml)
    if [ ${#files[@]} -eq 0 ]; then
        echo "nothing rendered — run just _render first"
        exit 1
    fi
    kubeconform -strict -summary \
        -schema-location default \
        -schema-location '{{ kubeconform_schemas }}' \
        "${files[@]}"

# static-analyse every rendered scenario
kube-linter:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    files=({{ render_dir }}/*.yaml)
    if [ ${#files[@]} -eq 0 ]; then
        echo "nothing rendered — run just _render first"
        exit 1
    fi
    kube-linter lint --config .kube-linter.yaml "${files[@]}"

# run the helm-unittest suites
unittest: deps
    helm unittest --strict charts/*/

# every chart ships a parseable values.schema.json
# (whether the schema accepts real values is covered by `just render`, which
# goes through helm template and therefore through schema validation)
schema:
    #!/usr/bin/env bash
    set -euo pipefail
    for chart in charts/*/; do
        schema="$chart/values.schema.json"
        [ -f "$schema" ] || { echo "FAIL  $chart has no values.schema.json"; exit 1; }
        yq -p json -o json '.' "$schema" > /dev/null || { echo "FAIL  $schema is not valid JSON"; exit 1; }
        echo "  ok    $schema"
    done

# chart READMEs are generated; fail if they are stale
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    helm-docs --chart-search-root=charts --template-files=README.md.gotmpl
    # --porcelain rather than a diff: a README that was never checked in at all
    # does not show up in `git diff`, so a diff-only gate would pass on it.
    changed=$(git status --porcelain -- 'charts/*/README.md')
    if [ -n "$changed" ]; then
        echo "FAIL  chart READMEs are stale — regenerate and check in the output"
        echo "$changed"
        exit 1
    fi
    echo "  ok    chart READMEs current"

# chart-testing lint, the checks helm lint does not do
ct-lint:
    ct lint --config ct.yaml --all

# ── live cluster ──────────────────────────────────────────────────────────────

# create the kind cluster the live gates run against
kind-up:
    #!/usr/bin/env bash
    set -euo pipefail
    if kind get clusters 2>/dev/null | grep -qx '{{ kind_cluster }}'; then
        echo "cluster {{ kind_cluster }} already exists"
        exit 0
    fi
    kind create cluster --name {{ kind_cluster }} --wait 120s

kind-down:
    -kind delete cluster --name {{ kind_cluster }}

# install the CRDs the render scenarios reference (no controllers)
crds:
    ./hack/install-crds.sh

# install the operators the end-to-end run actually needs
operators:
    ./hack/install-operators.sh

# the claim the repo exists to make: a realm file in git becomes users,
# groups and role mappings in a running Keycloak
e2e:
    ./hack/e2e.sh

# the bare-cluster claim: with every mode off, the charts install on a cluster
# that has no CRDs at all
e2e-bare:
    ./hack/e2e-bare.sh

# ── hygiene ───────────────────────────────────────────────────────────────────

hygiene:
    typos
    just editorconfig
    shellcheck hack/*.sh

editorconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    for name in ec editorconfig-checker; do
        if command -v "$name" > /dev/null 2>&1; then
            exec "$name"
        fi
    done
    echo "no editorconfig checker on PATH; looked for ec and editorconfig-checker" >&2
    exit 1

fmt:
    just --unstable --fmt

fmt-check:
    just --unstable --fmt --check

yaml:
    yamllint --strict .

workflows:
    yamllint --strict .github
    actionlint .github/workflows/*.yaml
    zizmor --no-online-audits .github/workflows/*.yaml

links:
    lychee --config lychee.toml .

commits:
    #!/usr/bin/env bash
    set -euo pipefail
    from=$(node -p "try { const e = require(process.env.GITHUB_EVENT_PATH); (e.pull_request ? e.pull_request.base.sha : e.before) || '' } catch (e) { '' }")
    if [ -z "$from" ] || ! git cat-file -e "$from^{commit}" 2>/dev/null; then
        from=HEAD~1
    fi
    npx --yes --package @commitlint/cli@21.2.2 --package @commitlint/config-conventional@21.2.2 commitlint --from "$from" --to HEAD

# ── supply chain ──────────────────────────────────────────────────────────────

secrets:
    gitleaks dir . --no-banner --redact
    gitleaks git . --no-banner --redact

sast:
    semgrep scan --config p/kubernetes --config p/secrets --error --quiet

# Scans the rendered scenarios rather than the chart sources: trivy's Helm
# scanner renders with default values, which these charts reject on purpose,
# so pointing it at charts/ makes it skip both and report a clean zero.
vulns: _render
    #!/usr/bin/env bash
    set -euo pipefail
    scanned=$(find {{ render_dir }} -name '*.yaml' | wc -l | tr -d ' ')
    if [ "$scanned" -eq 0 ]; then
        echo "FAIL  nothing rendered to scan"
        exit 1
    fi
    echo "scanning $scanned rendered scenarios"
    # --ignorefile explicitly: trivy auto-detects .trivyignore but not the
    # yaml form, and the yaml form is the one that records why.
    trivy config --exit-code 1 --severity HIGH,CRITICAL --skip-version-check \
        --ignorefile .trivyignore.yaml {{ render_dir }}
    # There are no dependency lockfiles in a chart repo today, and osv-scanner
    # exits 128 to say so. That is reported rather than swallowed, so the day a
    # lockfile appears the gate starts meaning something without being edited.
    set +e
    osv-scanner scan source --recursive .
    osv_status=$?
    set -e
    if [ "$osv_status" -eq 128 ]; then
        echo "  note  osv-scanner found no package sources to scan"
    elif [ "$osv_status" -ne 0 ]; then
        exit "$osv_status"
    fi

sbom:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p dist
    syft scan dir:. --source-name helm-charts --output cyclonedx-json=dist/sbom.cdx.json
    grype sbom:dist/sbom.cdx.json --fail-on medium

# scan every container image the charts can pull, not just the chart source
images: _render
    #!/usr/bin/env bash
    set -euo pipefail
    images=$(yq -N 'select(.spec != null) | .. | select(has("image")) | .image' {{ render_dir }}/*.yaml \
        | grep -v '^null$' | sort -u)
    if [ -z "$images" ]; then
        echo "no images found in the rendered scenarios — the extraction is broken"
        exit 1
    fi
    echo "$images"
    fail=0
    for image in $images; do
        echo "==> $image"
        trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "$image" || fail=1
    done
    exit $fail
