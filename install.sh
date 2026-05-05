#!/bin/bash
# 🧠 Fullstack Claude Skill Pack — Selective Installer
#
# Install everything:     curl -sL https://raw.githubusercontent.com/iamzaheershaik/fullstack-claude-skill-pack/main/install.sh | bash
# Install one category:   curl -sL https://raw.githubusercontent.com/iamzaheershaik/fullstack-claude-skill-pack/main/install.sh | bash -s -- backend
# Install multiple:       curl -sL https://raw.githubusercontent.com/iamzaheershaik/fullstack-claude-skill-pack/main/install.sh | bash -s -- backend frontend
# Install single skill:   curl -sL https://raw.githubusercontent.com/iamzaheershaik/fullstack-claude-skill-pack/main/install.sh | bash -s -- auth-system
#
# Categories: backend, frontend, devops, testing, tooling, pro, all
# Individual skills: auth-system, api-design, database-patterns, react-patterns, etc.

set -e

REPO="https://github.com/iamzaheershaik/fullstack-claude-skill-pack.git"
INSTALL_DIR="$HOME/fullstack-claude-skill-pack"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
BASE="~/fullstack-claude-skill-pack/skills"

# ── Skill Definitions ──────────────────────────────────────

declare -A CATEGORIES
CATEGORIES=(
  [backend]="backend/production-app-builder.md backend/auth-system.md backend/api-design.md backend/database-patterns.md"
  [frontend]="frontend/frontend-design.md frontend/react-patterns.md frontend/performance-audit.md frontend/component-library.md"
  [devops]="devops/docker-compose-builder.md devops/ci-cd-pipeline.md devops/monitoring-setup.md"
  [testing]="testing/test-writer.md testing/mock-factory.md"
  [tooling]="tooling/mern-scaffolder.md tooling/code-reviewer.md tooling/debug-assistant.md"
  [pro]="pro/saas-boilerplate.md pro/stripe-integration.md pro/real-time-patterns.md pro/multi-tenant-saas.md pro/ai-integration.md pro/email-system.md pro/admin-dashboard.md pro/deployment-playbook.md"
)

# Map individual skill names to paths
declare -A SKILL_MAP
SKILL_MAP=(
  # Backend
  [production-app-builder]="backend/production-app-builder.md"
  [auth-system]="backend/auth-system.md"
  [api-design]="backend/api-design.md"
  [database-patterns]="backend/database-patterns.md"
  # Frontend
  [frontend-design]="frontend/frontend-design.md"
  [react-patterns]="frontend/react-patterns.md"
  [performance-audit]="frontend/performance-audit.md"
  [component-library]="frontend/component-library.md"
  # DevOps
  [docker-compose-builder]="devops/docker-compose-builder.md"
  [ci-cd-pipeline]="devops/ci-cd-pipeline.md"
  [monitoring-setup]="devops/monitoring-setup.md"
  # Testing
  [test-writer]="testing/test-writer.md"
  [mock-factory]="testing/mock-factory.md"
  # Tooling
  [mern-scaffolder]="tooling/mern-scaffolder.md"
  [code-reviewer]="tooling/code-reviewer.md"
  [debug-assistant]="tooling/debug-assistant.md"
  # Pro
  [saas-boilerplate]="pro/saas-boilerplate.md"
  [stripe-integration]="pro/stripe-integration.md"
  [real-time-patterns]="pro/real-time-patterns.md"
  [multi-tenant-saas]="pro/multi-tenant-saas.md"
  [ai-integration]="pro/ai-integration.md"
  [email-system]="pro/email-system.md"
  [admin-dashboard]="pro/admin-dashboard.md"
  [deployment-playbook]="pro/deployment-playbook.md"
)

# ── Functions ──────────────────────────────────────────────

show_help() {
  echo ""
  echo "🧠 Fullstack Claude Skill Pack — Installer"
  echo "============================================"
  echo ""
  echo "Usage:"
  echo "  install.sh                     Install ALL skills"
  echo "  install.sh <category>          Install a category"
  echo "  install.sh <skill>             Install a single skill"
  echo "  install.sh <a> <b> <c>         Install multiple categories/skills"
  echo "  install.sh --list              Show all available skills"
  echo "  install.sh --help              Show this help"
  echo ""
  echo "Categories: backend, frontend, devops, testing, tooling, pro, all"
  echo ""
  echo "Examples:"
  echo "  install.sh backend             Install all 4 backend skills"
  echo "  install.sh auth-system         Install only auth-system skill"
  echo "  install.sh backend frontend    Install backend + frontend skills"
  echo "  install.sh stripe-integration ai-integration   Install 2 pro skills"
  echo ""
}

show_list() {
  echo ""
  echo "📋 Available Skills"
  echo "==================="
  echo ""
  echo "🏗️  backend (4 skills)"
  echo "    production-app-builder  auth-system  api-design  database-patterns"
  echo ""
  echo "🎨 frontend (4 skills)"
  echo "    frontend-design  react-patterns  performance-audit  component-library"
  echo ""
  echo "☁️  devops (3 skills)"
  echo "    docker-compose-builder  ci-cd-pipeline  monitoring-setup"
  echo ""
  echo "🧪 testing (2 skills)"
  echo "    test-writer  mock-factory"
  echo ""
  echo "🔧 tooling (3 skills)"
  echo "    mern-scaffolder  code-reviewer  debug-assistant"
  echo ""
  echo "⭐ pro (8 skills)"
  echo "    saas-boilerplate  stripe-integration  real-time-patterns  multi-tenant-saas"
  echo "    ai-integration  email-system  admin-dashboard  deployment-playbook"
  echo ""
}

resolve_skills() {
  local SKILLS=""
  for arg in "$@"; do
    if [ "$arg" = "all" ]; then
      for cat in "${!CATEGORIES[@]}"; do
        SKILLS="$SKILLS ${CATEGORIES[$cat]}"
      done
    elif [ -n "${CATEGORIES[$arg]}" ]; then
      SKILLS="$SKILLS ${CATEGORIES[$arg]}"
    elif [ -n "${SKILL_MAP[$arg]}" ]; then
      SKILLS="$SKILLS ${SKILL_MAP[$arg]}"
    else
      echo "❌ Unknown skill or category: $arg"
      echo "   Run with --list to see available options."
      exit 1
    fi
  done
  echo "$SKILLS"
}

# ── Main ───────────────────────────────────────────────────

# Handle flags
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  show_help
  exit 0
fi

if [ "$1" = "--list" ] || [ "$1" = "-l" ]; then
  show_list
  exit 0
fi

echo ""
echo "🧠 Fullstack Claude Skill Pack — Installer"
echo "============================================"
echo ""

# Step 1: Clone or update repo
if [ -d "$INSTALL_DIR" ]; then
  echo "📦 Updating existing installation..."
  cd "$INSTALL_DIR" && git pull --quiet
  echo "   ✅ Updated to latest version"
else
  echo "📦 Cloning skill pack..."
  git clone --quiet "$REPO" "$INSTALL_DIR"
  echo "   ✅ Cloned to $INSTALL_DIR"
fi

# Step 2: Resolve which skills to install
if [ $# -eq 0 ]; then
  SELECTED=$(resolve_skills all)
  echo "⚙️  Installing: ALL skills (24)"
else
  SELECTED=$(resolve_skills "$@")
  echo "⚙️  Installing: $*"
fi

# Step 3: Build CLAUDE.md entries
mkdir -p "$CLAUDE_DIR"

# Remove old skill pack entries if they exist
if [ -f "$CLAUDE_MD" ]; then
  # Remove everything between markers
  sed -i '/^# Fullstack Claude Skill Pack$/,/^# END Fullstack Claude Skill Pack$/d' "$CLAUDE_MD" 2>/dev/null || true
fi

# Add selected skills
{
  echo ""
  echo "# Fullstack Claude Skill Pack"
  echo "# https://github.com/iamzaheershaik/fullstack-claude-skill-pack"
  echo "# When building apps, read and follow these skill files as needed:"
  echo ""
  for skill in $SELECTED; do
    echo "- $BASE/$skill"
  done
  echo ""
  echo "# END Fullstack Claude Skill Pack"
} >> "$CLAUDE_MD"

# Count installed
SKILL_COUNT=$(echo "$SELECTED" | wc -w | tr -d ' ')

echo "   ✅ $SKILL_COUNT skill(s) added to $CLAUDE_MD"

echo ""
echo "============================================"
echo "✅ Installation complete!"
echo ""
echo "📁 Skills at:  $INSTALL_DIR"
echo "⚙️  Config at:   $CLAUDE_MD"
echo ""
echo "🚀 Open Claude Code — skills are active now."
echo "🔄 Update:  cd ~/fullstack-claude-skill-pack && git pull"
echo "📋 List:    ~/fullstack-claude-skill-pack/install.sh --list"
echo ""
