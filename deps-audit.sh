#!/usr/bin/env bash
# Měsíční přehled závislostí přes všechny GitHub projekty
set -euo pipefail
REPORT_DIR="${REPORT_DIR:-.}"
DATE=$(date +%Y-%m-%d)
REPORT="${REPORT_DIR}/deps-report-${DATE}.md"
CLONE_DIR=$(mktemp -d)
OWNER="${1:-ParalenPlus}"
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
for cmd in gh jq node; do
  command -v "$cmd" &>/dev/null || { echo -e "${RED}Chybí: ${cmd}${NC}"; exit 1; }
done
detect_pm() {
  if [[ -f "pnpm-lock.yaml" ]]; then echo "pnpm"
  elif [[ -f "yarn.lock" ]]; then echo "yarn"
  else echo "npm"
  fi
}
echo -e "${CYAN}Načítám repozitáře pro ${OWNER}...${NC}"
REPOS=($(gh repo list "$OWNER" --json nameWithOwner -q '.[].nameWithOwner' --limit 100))
TOTAL=${#REPOS[@]}
echo -e "${GREEN}Nalezeno ${TOTAL} repozitářů${NC}"
[[ $TOTAL -eq 0 ]] && { echo "Žádné repozitáře."; exit 0; }
cat > "$REPORT" << EOF
# 📦 Přehled závislostí — ${DATE}
> Účet: **${OWNER}** | Projektů: **${TOTAL}**
---
EOF
TOTAL_OUTDATED=0; TOTAL_MAJOR=0; TOTAL_VULN=0; PROJECTS_WITH_ISSUES=0
for i in "${!REPOS[@]}"; do
  REPO="${REPOS[$i]}"
  REPO_NAME=$(basename "$REPO")
  NUM=$((i + 1))
  echo -e "\n${CYAN}[${NUM}/${TOTAL}] ${REPO}${NC}"
  REPO_DIR="${CLONE_DIR}/${REPO_NAME}"
  if ! gh repo clone "$REPO" "$REPO_DIR" -- --depth 1 --quiet 2>/dev/null; then
    echo -e "  ${RED}Nelze klonovat${NC}"
    continue
  fi
  cd "$REPO_DIR"
  if [[ ! -f "package.json" ]]; then
    echo -e "  ${YELLOW}Není Node.js projekt${NC}"
    cd /; continue
  fi
  PM=$(detect_pm)
  # Detekce frameworku
  FRAMEWORK=""
  for fw in astro payload next; do
    VER=$(jq -r "(.dependencies.${fw} // .devDependencies.${fw}) // empty" package.json 2>/dev/null)
    [[ -n "$VER" ]] && FRAMEWORK="${FRAMEWORK:+$FRAMEWORK + }${fw} ${VER}"
  done
  FRAMEWORK="${FRAMEWORK:-Node.js}"
  # Zastaralé balíčky
  echo -e "  Kontroluji zastaralé..."
  OUTDATED_JSON=$(${PM} outdated --json 2>/dev/null || echo "{}")

  if [[ "$PM" == "pnpm" ]]; then
    OUTDATED_COUNT=$(echo "$OUTDATED_JSON" | jq 'if type=="array" then length elif type=="object" then (keys|length) else 0 end' 2>/dev/null || echo "0")
  else
    OUTDATED_COUNT=$(echo "$OUTDATED_JSON" | jq 'keys|length' 2>/dev/null || echo "0")
  fi
  # Zranitelnosti
  echo -e "  Kontroluji zranitelnosti..."
  AUDIT_JSON=$(npm audit --json 2>/dev/null || echo '{}')
  VULN_COUNT=$(echo "$AUDIT_JSON" | jq '.metadata.vulnerabilities // {} | [.moderate//0, .high//0, .critical//0] | add' 2>/dev/null || echo "0")
  VULN_HIGH=$(echo "$AUDIT_JSON" | jq '.metadata.vulnerabilities // {} | [.high//0, .critical//0] | add' 2>/dev/null || echo "0")
  TOTAL_OUTDATED=$((TOTAL_OUTDATED + OUTDATED_COUNT))
  TOTAL_VULN=$((TOTAL_VULN + VULN_COUNT))
  [[ "$OUTDATED_COUNT" -gt 0 || "$VULN_COUNT" -gt 0 ]] && PROJECTS_WITH_ISSUES=$((PROJECTS_WITH_ISSUES + 1))
  # Ikona
  if [[ "$VULN_HIGH" -gt 0 ]]; then ICON="🔴"
  elif [[ "$OUTDATED_COUNT" -gt 5 ]]; then ICON="🟡"
  elif [[ "$OUTDATED_COUNT" -gt 0 ]]; then ICON="🟠"
  else ICON="🟢"
  fi
  cat >> "$REPORT" << EOF
## ${ICON} ${REPO_NAME}
**Stack:** ${FRAMEWORK} | **PM:** ${PM} | **Zastaralé:** ${OUTDATED_COUNT} | **Zranitelnosti:** ${VULN_COUNT}
EOF
  echo -e "  ${ICON} Zastaralé: ${OUTDATED_COUNT} | Zranitelnosti: ${VULN_COUNT}"
  cd /
done
cat >> "$REPORT" << EOF
---
# 📊 Souhrn
| Metrika | Hodnota |
|---------|---------|
| Celkem projektů | ${TOTAL} |
| S problémy | ${PROJECTS_WITH_ISSUES} |
| Zastaralých balíčků | ${TOTAL_OUTDATED} |
| Zranitelností | ${TOTAL_VULN} |
EOF
rm -rf "$CLONE_DIR"
echo -e "\n${GREEN}Report: ${REPORT}${NC}"
echo -e "${GREEN}Projektů: ${TOTAL} | S problémy: ${PROJECTS_WITH_ISSUES} | Zastaralé: ${TOTAL_OUTDATED} | Zranitelnosti: ${TOTAL_VULN}${NC}"
