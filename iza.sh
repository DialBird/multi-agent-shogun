#!/bin/bash
# 🏯 iza - multi-agent-shogun 起動スクリプト
# "いざ" - Let's go! / Here we go!
#
# 使用方法:
#   iza                          # カレントディレクトリのプロジェクトで起動
#   iza -p <project_name>        # 指定プロジェクトで起動
#   iza -s                       # セットアップのみ（Claude起動なし）
#   iza -h                       # ヘルプ表示

set -e

# スクリプトのディレクトリを取得（シンボリックリンクを解決、Bash/Zsh両対応）
if [ -n "${BASH_SOURCE[0]}" ]; then
    SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [ -n "$ZSH_VERSION" ]; then
    SCRIPT_PATH="${(%):-%x}"
else
    SCRIPT_PATH="$0"
fi
while [ -L "$SCRIPT_PATH" ]; do
    LINK_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$LINK_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# 呼び出し元のディレクトリを保存
CALLER_DIR="$(pwd)"

cd "$SCRIPT_DIR"

# 言語設定を読み取り（デフォルト: ja）
LANG_SETTING="ja"
if [ -f "./config/settings.yaml" ]; then
    LANG_SETTING=$(grep "^language:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "ja")
fi

# 色付きログ関数（戦国風）
log_info() {
    echo -e "\033[1;33m【報】\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m【成】\033[0m $1"
}

log_war() {
    echo -e "\033[1;31m【戦】\033[0m $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# オプション解析
# ═══════════════════════════════════════════════════════════════════════════════
SETUP_ONLY=false
OPEN_TERMINAL=false
KILL_MODE=false
KILL_ALL=false
PROJECT_NAME=""
SILENT_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -s|--setup-only)
            SETUP_ONLY=true
            shift
            ;;
        -t|--terminal)
            OPEN_TERMINAL=true
            shift
            ;;
        -k|--kill)
            KILL_MODE=true
            shift
            ;;
        --kill-all)
            KILL_ALL=true
            shift
            ;;
        -S|--silent)
            SILENT_MODE=true
            shift
            ;;
        -h|--help)
            echo ""
            echo "🏯 iza - multi-agent-shogun 起動スクリプト"
            echo ""
            echo "使用方法:"
            echo "  iza                    # カレントディレクトリのプロジェクトで起動"
            echo "  iza -p <project_name>  # 指定プロジェクトで起動"
            echo "  iza -k                 # カレントプロジェクトのセッションを終了"
            echo "  iza --kill-all         # 全プロジェクトのセッションを終了"
            echo ""
            echo "オプション:"
            echo "  -p, --project     プロジェクト名を明示的に指定"
            echo "  -s, --setup-only  tmuxセッションのセットアップのみ（Claude起動なし）"
            echo "  -t, --terminal    Windows Terminal で新しいタブを開く"
            echo "  -k, --kill        指定プロジェクトのセッションを終了（撤退）"
            echo "  --kill-all        全プロジェクトのセッションを終了（総撤退）"
            echo "  -S, --silent      サイレントモード（足軽の戦国echo表示を無効化・API節約）"
            echo "  -h, --help        このヘルプを表示"
            echo ""
            echo "例:"
            echo "  cd ~/myproject && iza  # myprojectディレクトリから起動（自動検出）"
            echo "  iza -p myapp           # myappプロジェクトで出陣"
            echo "  iza -p myapp -s        # セットアップのみ"
            echo "  iza -k                 # カレントプロジェクトを撤退"
            echo "  iza -p myapp -k        # myappプロジェクトを撤退"
            echo "  iza --kill-all         # 全軍撤退"
            echo "  iza -S                 # サイレントモード（echo表示なし）"
            echo ""
            echo "プロジェクト別セッション:"
            echo "  tmux attach-session -t myapp-shogun"
            echo "  tmux attach-session -t myapp-multiagent"
            echo ""
            echo "モデル構成:"
            echo "  将軍:      Opus"
            echo "  家老:      Opus"
            echo "  足軽1-4:   Sonnet"
            echo "  足軽5:     Opus"
            echo ""
            exit 0
            ;;
        *)
            echo "不明なオプション: $1"
            echo "iza -h でヘルプを表示"
            exit 1
            ;;
    esac
done

# ═══════════════════════════════════════════════════════════════════════════════
# プロジェクト自動検出（-p が指定されていない場合）
# ═══════════════════════════════════════════════════════════════════════════════
if [ -z "$PROJECT_NAME" ]; then
    log_info "🔍 プロジェクトを検索中..."

    # projects/*/config.yaml をスキャンして、path が CALLER_DIR と一致するものを探す
    FOUND_PROJECT=""
    for config_file in "$SCRIPT_DIR"/projects/*/config.yaml; do
        if [ -f "$config_file" ]; then
            # config.yaml から path を抽出
            PROJECT_PATH=$(grep "^  path:" "$config_file" 2>/dev/null | sed 's/^  path: *//' | sed 's/"//g' | sed "s/'//g")

            # 空でない path が CALLER_DIR と一致するか確認
            if [ -n "$PROJECT_PATH" ] && [ "$PROJECT_PATH" = "$CALLER_DIR" ]; then
                # プロジェクトIDを取得（ディレクトリ名）
                FOUND_PROJECT=$(basename "$(dirname "$config_file")")
                break
            fi
        fi
    done

    if [ -n "$FOUND_PROJECT" ]; then
        # 既存プロジェクトが見つかった
        PROJECT_NAME="$FOUND_PROJECT"
        log_success "  └─ 既存プロジェクト発見: ${PROJECT_NAME}"
    else
        # 新規プロジェクト作成（対話式）
        echo ""
        echo -e "\033[1;33m【新】\033[0m カレントディレクトリ: $CALLER_DIR"
        echo -e "      このディレクトリは未登録です。"
        echo ""
        echo -n "プロジェクトIDを入力してください（英数字とハイフンのみ）: "
        read -r PROJECT_NAME

        # 入力検証
        if [ -z "$PROJECT_NAME" ]; then
            echo -e "\033[1;31m【錯】\033[0m プロジェクトIDが入力されておりませぬ！"
            exit 1
        fi

        # 英数字とハイフンのみ許可
        if ! [[ "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo -e "\033[1;31m【錯】\033[0m プロジェクトIDは英数字、ハイフン、アンダースコアのみ使用可能です。"
            exit 1
        fi

        # 重複チェック
        if [ -d "$SCRIPT_DIR/projects/$PROJECT_NAME" ]; then
            echo ""
            echo -e "\033[1;31m【警】\033[0m プロジェクト '$PROJECT_NAME' は既に存在します！"
            echo ""
            # 既存プロジェクトの path を表示
            EXISTING_PATH=$(grep "^  path:" "$SCRIPT_DIR/projects/$PROJECT_NAME/config.yaml" 2>/dev/null | sed 's/^  path: *//' | sed 's/"//g' | sed "s/'//g")
            echo "      既存の path: $EXISTING_PATH"
            echo "      現在の path: $CALLER_DIR"
            echo ""
            echo -n "既存プロジェクトの path を上書きしますか？ (y/N): "
            read -r OVERWRITE
            if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
                # path を上書き
                sed -i '' "s|^  path:.*|  path: \"$CALLER_DIR\"|" "$SCRIPT_DIR/projects/$PROJECT_NAME/config.yaml"
                log_success "  └─ path を上書きしました"
            else
                echo "中止しました。"
                exit 1
            fi
        else
            # 新規プロジェクトとしてマーク（後で作成）
            NEW_PROJECT=true
        fi
    fi
    echo ""
fi

# セッション名を定義
SHOGUN_SESSION="${PROJECT_NAME}-shogun"
MULTIAGENT_SESSION="${PROJECT_NAME}-multiagent"

# プロジェクトディレクトリを定義
PROJECT_DIR="./projects/${PROJECT_NAME}"

# ═══════════════════════════════════════════════════════════════════════════════
# KILL モード処理（-k または --kill-all が指定された場合）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$KILL_ALL" = true ]; then
    echo ""
    echo -e "\033[1;31m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;31m║\033[0m                        \033[1;37m【 総 撤 退 】全軍撤収！\033[0m                                \033[1;31m║\033[0m"
    echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    # 全ての *-shogun と *-multiagent セッションを終了
    KILLED_COUNT=0
    for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E "(-shogun$|-multiagent$)"); do
        tmux kill-session -t "$session" 2>/dev/null
        log_success "  └─ ${session} 撤収完了"
        ((KILLED_COUNT++))
    done

    if [ "$KILLED_COUNT" -eq 0 ]; then
        log_info "  └─ 撤収対象のセッションは存在せず"
    else
        echo ""
        log_success "✅ 全${KILLED_COUNT}セッション撤収完了。お疲れ様でござった！"
    fi
    echo ""
    exit 0
fi

if [ "$KILL_MODE" = true ]; then
    echo ""
    echo -e "\033[1;33m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;33m║\033[0m                    \033[1;37m【 撤 退 】${PROJECT_NAME} 軍撤収！\033[0m                              \033[1;33m║\033[0m"
    echo -e "\033[1;33m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    KILLED=false
    if tmux has-session -t "$SHOGUN_SESSION" 2>/dev/null; then
        tmux kill-session -t "$SHOGUN_SESSION"
        log_success "  └─ ${SHOGUN_SESSION} 本陣、撤収完了"
        KILLED=true
    fi
    if tmux has-session -t "$MULTIAGENT_SESSION" 2>/dev/null; then
        tmux kill-session -t "$MULTIAGENT_SESSION"
        log_success "  └─ ${MULTIAGENT_SESSION} 陣、撤収完了"
        KILLED=true
    fi

    if [ "$KILLED" = false ]; then
        log_info "  └─ ${PROJECT_NAME} の陣は既に存在せず"
    else
        echo ""
        log_success "✅ ${PROJECT_NAME} 撤収完了。お疲れ様でござった！"
    fi
    echo ""
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 出陣バナー表示（CC0ライセンスASCIIアート使用）
# ───────────────────────────────────────────────────────────────────────────────
# 【著作権・ライセンス表示】
# 忍者ASCIIアート: syntax-samurai/ryu - CC0 1.0 Universal (Public Domain)
# 出典: https://github.com/syntax-samurai/ryu
# "all files and scripts in this repo are released CC0 / kopimi!"
# ═══════════════════════════════════════════════════════════════════════════════
show_battle_cry() {
    clear

    # タイトルバナー（色付き）
    echo ""
    echo -e "\033[1;31m╔══════════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████╗██╗  ██╗██╗   ██╗████████╗███████╗██╗   ██╗     ██╗██╗███╗   ██╗\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m██╔════╝██║  ██║██║   ██║╚══██╔══╝██╔════╝██║   ██║     ██║██║████╗  ██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████╗███████║██║   ██║   ██║   ███████╗██║   ██║     ██║██║██╔██╗ ██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m╚════██║██╔══██║██║   ██║   ██║   ╚════██║██║   ██║██   ██║██║██║╚██╗██║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m███████║██║  ██║╚██████╔╝   ██║   ███████║╚██████╔╝╚█████╔╝██║██║ ╚████║\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m║\033[0m \033[1;33m╚══════╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝  ╚════╝ ╚═╝╚═╝  ╚═══╝\033[0m \033[1;31m║\033[0m"
    echo -e "\033[1;31m╠══════════════════════════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;31m║\033[0m       \033[1;37m出陣じゃーーー！！！\033[0m    \033[1;36m⚔\033[0m    \033[1;35m天下布武！\033[0m                          \033[1;31m║\033[0m"
    echo -e "\033[1;31m╚══════════════════════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # 足軽隊列（オリジナル）
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;34m  ╔═════════════════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;34m  ║\033[0m                    \033[1;37m【 足 軽 隊 列 ・ 五 名 配 備 】\033[0m                      \033[1;34m║\033[0m"
    echo -e "\033[1;34m  ╚═════════════════════════════════════════════════════════════════════════════╝\033[0m"

    cat << 'ASHIGARU_EOF'

       /\      /\      /\      /\      /\
      /||\    /||\    /||\    /||\    /||\
     /_||\   /_||\   /_||\   /_||\   /_||\
       ||      ||      ||      ||      ||
      /||\    /||\    /||\    /||\    /||\
      /  \    /  \    /  \    /  \    /  \
     [足1]   [足2]   [足3]   [足4]   [足5]

ASHIGARU_EOF

    echo -e "                    \033[1;36m「「「 はっ！！ 出陣いたす！！ 」」」\033[0m"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # システム情報
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;33m  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\033[0m"
    echo -e "\033[1;33m  ┃\033[0m  \033[1;37m🏯 multi-agent-shogun\033[0m  〜 \033[1;36m戦国マルチエージェント統率システム\033[0m 〜           \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m                                                                           \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┃\033[0m    \033[1;35m将軍\033[0m: プロジェクト統括    \033[1;31m家老\033[0m: タスク管理    \033[1;34m足軽\033[0m: 実働部隊×5      \033[1;33m┃\033[0m"
    echo -e "\033[1;33m  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m"
    echo ""
}

# バナー表示実行
show_battle_cry

echo -e "  \033[1;33m天下布武！陣立てを開始いたす\033[0m (Setting up the battlefield)"
echo -e "  \033[1;36m【戦場】\033[0m ${PROJECT_NAME}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 0: プロジェクトディレクトリ作成
# ═══════════════════════════════════════════════════════════════════════════════
if [ ! -d "$PROJECT_DIR" ]; then
    log_info "📁 プロジェクト陣地を新設中: ${PROJECT_NAME}..."

    # ディレクトリ構造を作成
    mkdir -p "${PROJECT_DIR}/queue/tasks"
    mkdir -p "${PROJECT_DIR}/queue/reports"
    mkdir -p "${PROJECT_DIR}/memory"
    mkdir -p "${PROJECT_DIR}/skills/generated"
    mkdir -p "${PROJECT_DIR}/history/commands"
    mkdir -p "${PROJECT_DIR}/history/sessions"

    # path を決定（CALLER_DIR が multi-agent-shogun 自体でなければ使用）
    if [ "$CALLER_DIR" != "$SCRIPT_DIR" ]; then
        PROJECT_CODE_PATH="$CALLER_DIR"
    else
        PROJECT_CODE_PATH=""
    fi

    # config.yaml を作成（プロジェクト設定）
    cat > "${PROJECT_DIR}/config.yaml" << EOF
# プロジェクト設定
project:
  id: ${PROJECT_NAME}
  name: "${PROJECT_NAME}"
  path: "${PROJECT_CODE_PATH}"

  # 追加情報（任意）
  description: ""
  notion_url: ""
  github_url: ""

  # プロジェクト固有の設定
  language: ja
  priority: normal  # high / normal / low
EOF

    # status.md を作成（プロジェクトの現在状況）
    cat > "${PROJECT_DIR}/status.md" << 'EOF'
# プロジェクト現在状況

このファイルはプロジェクトの現在状況を記録する。
コーディング規約等は対象プロジェクトの CLAUDE.md を参照せよ。

## 現在のフェーズ
- （例: MVP開発中、リファクタリング中、バグ修正中）

## 最近の重要決定
- YYYY-MM-DD: （決定内容）

## 現在のブロッカー
- なし

## 今週の目標
- （短期目標）

## 注意点
- （一時的な注意事項）
EOF

    log_success "  └─ プロジェクトディレクトリ作成完了"
    log_info "  └─ ${PROJECT_DIR}/config.yaml を編集してプロジェクトパスを設定してください"
else
    log_info "📁 既存のプロジェクト陣地を使用: ${PROJECT_NAME}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: 既存セッションクリーンアップ
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🧹 既存の陣を撤収中..."
tmux kill-session -t "$MULTIAGENT_SESSION" 2>/dev/null && log_info "  └─ ${MULTIAGENT_SESSION}陣、撤収完了" || log_info "  └─ ${MULTIAGENT_SESSION}陣は存在せず"
tmux kill-session -t "$SHOGUN_SESSION" 2>/dev/null && log_info "  └─ ${SHOGUN_SESSION}本陣、撤収完了" || log_info "  └─ ${SHOGUN_SESSION}本陣は存在せず"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: 報告ファイルリセット + inbox初期化
# ═══════════════════════════════════════════════════════════════════════════════
log_info "📜 前回の軍議記録を破棄中..."

# キューディレクトリ確保
[ -d "${PROJECT_DIR}/queue/reports" ] || mkdir -p "${PROJECT_DIR}/queue/reports"
[ -d "${PROJECT_DIR}/queue/tasks" ] || mkdir -p "${PROJECT_DIR}/queue/tasks"

# 足軽レポートファイルリセット
for i in {1..5}; do
    cat > "${PROJECT_DIR}/queue/reports/ashigaru${i}_report.yaml" << EOF
worker_id: ashigaru${i}
task_id: null
timestamp: ""
status: idle
result: null
EOF
done

# キューファイルリセット
cat > "${PROJECT_DIR}/queue/shogun_to_karo.yaml" << 'EOF'
queue: []
EOF

# ntfy inbox リセット
echo "inbox:" > "${PROJECT_DIR}/queue/ntfy_inbox.yaml"

# inbox はLinux FSにシンボリックリンク（WSL2の/mnt/c/ではinotifywaitが動かないため）
INBOX_LINUX_DIR="$HOME/.local/share/multi-agent-shogun/${PROJECT_NAME}/inbox"
mkdir -p "$INBOX_LINUX_DIR"

# root level queue/inbox → inbox_write.sh / inbox_watcher.sh が参照するパス
ROOT_INBOX="$SCRIPT_DIR/queue/inbox"
if [ -d "$ROOT_INBOX" ] && [ ! -L "$ROOT_INBOX" ]; then
    # 既存ファイルをLinux FSにコピーしてからシンボリックリンク化
    cp "$ROOT_INBOX"/*.yaml "$INBOX_LINUX_DIR/" 2>/dev/null || true
    rm -rf "$ROOT_INBOX"
fi
mkdir -p "$SCRIPT_DIR/queue"
[ -L "$ROOT_INBOX" ] && rm "$ROOT_INBOX"
ln -sf "$INBOX_LINUX_DIR" "$ROOT_INBOX"
log_info "  └─ inbox → Linux FS ($INBOX_LINUX_DIR) にシンボリックリンク作成"

# agent inbox ファイル初期化
for agent in shogun karo ashigaru{1..5}; do
    [ -f "$ROOT_INBOX/${agent}.yaml" ] || echo "messages: []" > "$ROOT_INBOX/${agent}.yaml"
done

log_success "✅ 陣払い完了"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: ダッシュボード初期化
# ═══════════════════════════════════════════════════════════════════════════════
log_info "📊 戦況報告板を初期化中..."
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

if [ "$LANG_SETTING" = "ja" ]; then
    # 日本語のみ
    cat > "${PROJECT_DIR}/dashboard.md" << EOF
# 📊 戦況報告
最終更新: ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております
なし

## 🔄 進行中 - 只今、戦闘中でござる
なし

## ✅ 本日の戦果
| 時刻 | 戦場 | 任務 | 結果 |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち
なし

## 🛠️ 生成されたスキル
なし

## ⏸️ 待機中
なし

## ❓ 伺い事項
なし
EOF
else
    # 日本語 + 翻訳併記
    cat > "${PROJECT_DIR}/dashboard.md" << EOF
# 📊 戦況報告 (Battle Status Report)
最終更新 (Last Updated): ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております (Action Required - Awaiting Lord's Decision)
なし (None)

## 🔄 進行中 - 只今、戦闘中でござる (In Progress - Currently in Battle)
なし (None)

## ✅ 本日の戦果 (Today's Achievements)
| 時刻 (Time) | 戦場 (Battlefield) | 任務 (Mission) | 結果 (Result) |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち (Skill Candidates - Pending Approval)
なし (None)

## 🛠️ 生成されたスキル (Generated Skills)
なし (None)

## ⏸️ 待機中 (On Standby)
なし (None)

## ❓ 伺い事項 (Questions for Lord)
なし (None)
EOF
fi

log_success "  └─ ダッシュボード初期化完了 (言語: $LANG_SETTING)"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: multiagentセッション作成（6ペイン：karo + ashigaru1-5）
# ═══════════════════════════════════════════════════════════════════════════════
log_war "⚔️ 家老・足軽の陣を構築中（6名配備）..."

# 最初のペイン作成
tmux new-session -d -s "$MULTIAGENT_SESSION" -n "agents"

# DISPLAY_MODE: shout (default) or silent (--silent flag)
if [ "$SILENT_MODE" = true ]; then
    tmux set-environment -t "$MULTIAGENT_SESSION" DISPLAY_MODE "silent"
    echo "  📢 表示モード: サイレント（echo表示なし）"
else
    tmux set-environment -t "$MULTIAGENT_SESSION" DISPLAY_MODE "shout"
fi

# 2x3グリッド作成（合計6ペイン: karo + ashigaru1-5）
tmux split-window -h -t "${MULTIAGENT_SESSION}:0"

# 各列を3行に分割
tmux select-pane -t "${MULTIAGENT_SESSION}:0.0"
tmux split-window -v
tmux split-window -v

tmux select-pane -t "${MULTIAGENT_SESSION}:0.3"
tmux split-window -v
tmux split-window -v

# エージェントID・モデル設定
AGENT_IDS=("karo" "ashigaru1" "ashigaru2" "ashigaru3" "ashigaru4" "ashigaru5")
MODEL_NAMES=("Opus" "Sonnet" "Sonnet" "Sonnet" "Sonnet" "Opus")

for i in {0..5}; do
    tmux select-pane -t "${MULTIAGENT_SESSION}:0.$i" -T "${MODEL_NAMES[$i]}"
    tmux set-option -p -t "${MULTIAGENT_SESSION}:0.$i" @agent_id "${AGENT_IDS[$i]}"
    tmux set-option -p -t "${MULTIAGENT_SESSION}:0.$i" @model_name "${MODEL_NAMES[$i]}"
    tmux set-option -p -t "${MULTIAGENT_SESSION}:0.$i" @current_task ""
    tmux send-keys -t "${MULTIAGENT_SESSION}:0.$i" "cd ${SCRIPT_DIR} && clear" Enter
done

# pane-border-format でモデル名を常時表示
tmux set-option -t "$MULTIAGENT_SESSION" -w pane-border-status top
tmux set-option -t "$MULTIAGENT_SESSION" -w pane-border-format '#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[default] (#{@model_name}) #{@current_task}'

log_success "  └─ 家老・足軽の陣、構築完了"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: shogunセッション作成（1ペイン）
# ═══════════════════════════════════════════════════════════════════════════════
log_war "👑 将軍の本陣を構築中..."
tmux new-session -d -s "$SHOGUN_SESSION"
tmux send-keys -t "$SHOGUN_SESSION" "cd ${SCRIPT_DIR} && clear" Enter

log_success "  └─ 将軍の本陣、構築完了"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Claude Code 起動（--setup-only でスキップ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$SETUP_ONLY" = false ]; then
    log_war "👑 全軍に Claude Code を召喚中..."

    # 将軍: Opus（thinking無効 = 中継特化）
    tmux send-keys -t "$SHOGUN_SESSION" "MAX_THINKING_TOKENS=0 claude --model opus --dangerously-skip-permissions"
    tmux send-keys -t "$SHOGUN_SESSION" Enter
    log_info "  └─ 将軍（Opus）、召喚完了"

    # 少し待機（安定のため）
    sleep 1

    # 家老（pane 0）: Opus
    tmux send-keys -t "${MULTIAGENT_SESSION}:0.0" "claude --model opus --dangerously-skip-permissions"
    tmux send-keys -t "${MULTIAGENT_SESSION}:0.0" Enter
    log_info "  └─ 家老（Opus）、召喚完了"

    # 足軽1-4: Sonnet
    for i in {1..4}; do
        tmux send-keys -t "${MULTIAGENT_SESSION}:0.$i" "claude --model sonnet --dangerously-skip-permissions"
        tmux send-keys -t "${MULTIAGENT_SESSION}:0.$i" Enter
    done
    log_info "  └─ 足軽1-4（Sonnet）、召喚完了"

    # 足軽5: Opus
    tmux send-keys -t "${MULTIAGENT_SESSION}:0.5" "claude --model opus --dangerously-skip-permissions"
    tmux send-keys -t "${MULTIAGENT_SESSION}:0.5" Enter
    log_info "  └─ 足軽5（Opus）、召喚完了"

    log_success "✅ 全軍 Claude Code 起動完了"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6.5: 各エージェントに指示書を読み込ませる
    # ═══════════════════════════════════════════════════════════════════════════
    log_war "📜 各エージェントに指示書を読み込ませ中..."
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # 忍者戦士（syntax-samurai/ryu - CC0 1.0 Public Domain）
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "\033[1;35m  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m  │\033[0m                              \033[1;37m【 忍 者 戦 士 】\033[0m  Ryu Hayabusa (CC0 Public Domain)                        \033[1;35m│\033[0m"
    echo -e "\033[1;35m  └────────────────────────────────────────────────────────────────────────────────────────────────────────────┘\033[0m"

    cat << 'NINJA_EOF'
...................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                        ...................................
..................................░░░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░▒▒▒▒▒▒▒                         ...................................
..................................░░░░░░░░░░░░░░░░▒▒▒▒          ▒▒▒▒▒▒▒▒░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒                             ...................................
..................................░░░░░░░░░░░░░░▒▒▒▒               ▒▒▒▒▒░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                ...................................
..................................░░░░░░░░░░░░░▒▒▒                    ▒▒▒▒░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                    ...................................
..................................░░░░░░░░░░░░▒                            ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                        ...................................
..................................░░░░░░░░░░░      ░░░░░░░░░░░░░                                      ░░░░░░░░░░░░       ▒          ...................................
..................................░░░░░░░░░░ ▒    ░░░▓▓▓▓▓▓▓▓▓▓▓▓░░                                 ░░░░░░░░░░░░░░░ ░               ...................................
..................................░░░░░░░░░░     ░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░                          ░░░░░░░░░░░░░░░░░░░                ...................................
..................................░░░░░░░░░ ▒  ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░             ░░▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░  ░   ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░ ░  ▒         ...................................
..................................░░░░░░░░ ░  ░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░  ░    ▒        ...................................
..................................░░░░░░░░░▒  ░ ░               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓░                 ░            ...................................
.................................░░░░░░░░░░   ░░░  ░                 ▓▓▓▓▓▓▓▓░▓▓▓▓░░░▓░░░░░░▓▓▓▓▓                    ░ ░   ▒         ..................................
.................................░░░░░░░░▒▒   ░░░░░ ░                  ▓▓▓▓▓▓░▓▓▓▓░░▓▓▓░░░░░░▓▓                    ░  ░ ░  ▒         ..................................
.................................░░░░░░░░▒    ░░░░░░░░░ ░                 ░▓░░▓▓▓▓▓░▓▓▓░░░░░                   ░ ░░ ░░ ░   ▒         ..................................
.................................░░░░░░░▒▒    ░░░░░░░   ░░                    ▓▓▓▓▓▓▓▓▓░░                   ░░    ░ ░░ ░    ▒        ..................................
.................................░░░░░░░▒▒    ░░░░░░░░░░                      ░▓▓▓▓▓▓▓░░░                     ░░░  ░  ░ ░   ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░                         ░░░▓▓▓░▓░░░░      ░                  ░ ░░ ░    ▒        ..................................
.................................░░░░░░░ ▒    ░░░░░░░     ▓▓        ▓  ░░ ░░░░░░░░░░░░░  ░   ░░  ▓        █▓       ░  ░ ░   ▒▒       ..................................
..................................░░░░░▒ ▒    ░░░░░░░░  ▓▓██  ▓  ██ ██▓  ▓ ░░░▓░  ░ ░ ░░░░  ▓   ██ ▓█  ▓  ██▓▓  ░░░░  ░ ░    ▒      ...................................
..................................░░░░░▒ ▒▒   ░░░░░░░░░  ▓██  ▓▓  ▓ ██▓  ▓░░░░▓▓░  ░░░░░░░░ ▓  ▓██ ▓   ▓  ██▓▓ ░░░░░░░ ░     ▒      ...................................
..................................░░░░░  ▒░   ░░░░░░░▓░░ ▓███  ▓▓▓▓ ███░  ░░░░▓▓░░░░░░░░░░    ░▓██  ▓▓▓  ███▓ ░░▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░  ▒░    ░░░░▓▓▓▓▓▓░  ███    ██      ░░░░░▓▓▓▓▓░░░░░░░     ███   ████ ░░▓▓▓▓░░  ░    ▒ ▒      ...................................
...................................░░░░ ▒ ░▒    ░░▓▓▓▓▓▓▓▓▓▓ ██████  ▓▓▓░░ ░░░░▓▓▓▓▓▓░░░░░░░░░▓▓▓   █████  ▓▓▓▓▓▓▓░░░░    ▒▒ ▒      ...................................
...................................░░░░ ░ ░░     ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█░░░░░░░▓▓▓▓▓▓▓░░░░ ░░   ░░▓░▓▓░░░░░░░▓▓▓▓▓▓░░      ▒▒ ▒      ...................................
...................................░░░░ ░ ░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██  ░░░░░░░▓▓▓▓▓▓▓░░░░  ░░░░░   ░░░░░░░░░▓▓▓▓▓░░ ░    ▒▒  ▒      ...................................
...................................░░░░▒░░▒░░      ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░▓▓▓▓▓▓▓▓░░░  ░░░░░░░░░░░░░░░░░░▓▓░░░░      ▒▒  ▒     ....................................
...................................░░░░▒░░ ░░       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░▓▓▓▓▓▓▓▓▓░░░░  ░░░░░░░░░░░░░░░░░░░░░        ▒▒  ▒     ....................................
...................................░░░░░░░ ▒░▒       ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░▓▓▓░░   ░░░░░  ░░░░░░░░░░░░░░░░░░░░         ▒   ▒     ....................................
...................................░░░░░░░░░░░           ░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓              ░    ░░░░░░░░░░░░░░░            ▒   ▒     ....................................
....................................░░░░░░░░░░░▒  ▒▒        ▓▓▓▓▓▓▓▓▓▓▓▓▓  ░░░░░░░░░░▒▒                         ▒▒▒▒▒   ▒    ▒    .....................................
....................................░░░░░░░░░░ ░▒ ▒▒▒░░░        ▓▓▓▓▓▓   ░░░░░░░░░░░░░▒▒▒      ▒▒▒▒▒░░░░▒▒    ▒▒▒▒▒▒▒  ▒▒    ▒    .....................................
....................................░░░░░░░░░░ ░░░ ▒▒▒░░░░░░          ░░░░░ ░░░░░░░░░░▒░▒     ▒▒▒▒▒▒░░░░░░▒▒▒▒▒░▒▒▒▒   ▒▒         .....................................
.....................................░░░░░░░░░░ ░░░░░  ▒▒░░░░░░░░░░░░░    ░░░░░░░░░  ▒░▒▒    ▒▒▒▒▒░░░░▒▒▒▒▒▒░░▒▒▒   ▒▒▒         ......................................
.....................................░░░░░░░░░░░░░░░░░░  ▒░░░░░░░░░░░   ░░░░░░░░░░░░░░   ▒   ▒▒▒▒▒▒▒░▒▒▒▒▒▒░░░░▒▒▒   ▒▒          ......................................
.....................................░░░░░░░░░░░ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░      ▒▒▒▒▒▒▒    ▒  ░░░▒▒▒▒  ▒▒▒          ......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ▒░▒▒▒ ▒▒▒    ▒░░░░░░░░░░▒   ▒▒▒▒      ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒  ░░▒▒▒▒▒▒░░░░░░░░░░░░░▒  ░▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒ ▒▒░▒▒▒▒▒▒▒░░░░░░░░░░  ░░▒▒▒▒▒       ▒   .......................................
......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒ ░▒▒▒▒▒▒▒▒▒░░▒░░░░░░ ░░▒▒▒▒▒▒      ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒░░▒░▒▒▒ ▒▒▒▒▒░░░░░░░░░▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒▒░▒▒▒▒▒     ░░░░░░░░▒▒▒▒▒▒        ▒    .......................................
.......................................░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▒░░▒░▒▒▒▒▒▒  ▒░░░░░░░▒▒▒▒▒▒        ▒     .......................................
NINJA_EOF

    echo ""
    echo -e "                                    \033[1;35m「 天下布武！勝利を掴め！ 」\033[0m"
    echo ""
    echo -e "                               \033[0;36m[ASCII Art: syntax-samurai/ryu - CC0 1.0 Public Domain]\033[0m"
    echo ""

    echo "  Claude Code の起動を待機中（15秒）..."
    sleep 15

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 6.6: inbox_watcher起動（全エージェント）
    # ═══════════════════════════════════════════════════════════════════════════
    log_info "📬 メールボックス監視を起動中..."

    mkdir -p "$SCRIPT_DIR/logs"

    # 既存のwatcherと孤児inotifywaitをkill
    pkill -f "inbox_watcher.sh" 2>/dev/null || true
    pkill -f "inotifywait.*queue/inbox" 2>/dev/null || true
    sleep 1

    # 将軍のwatcher
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" shogun "${SHOGUN_SESSION}:0.0" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_shogun.log" &
    disown

    # 家老のwatcher
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" karo "${MULTIAGENT_SESSION}:0.0" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_karo.log" &
    disown

    # 足軽のwatcher（1-5）
    for i in {1..5}; do
        nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "ashigaru${i}" "${MULTIAGENT_SESSION}:0.${i}" \
            &>> "$SCRIPT_DIR/logs/inbox_watcher_ashigaru${i}.log" &
        disown
    done

    log_success "  └─ 7エージェント分のinbox_watcher起動完了"

    # 指示書読み込みは各エージェントが自律実行（CLAUDE.md Session Start）
    log_info "📜 指示書読み込みは各エージェントが自律実行（CLAUDE.md Session Start）"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6.8: ntfy入力リスナー起動
# ═══════════════════════════════════════════════════════════════════════════════
NTFY_TOPIC=$(grep 'ntfy_topic:' ./config/settings.yaml 2>/dev/null | awk '{print $2}' | tr -d '"')
if [ -n "$NTFY_TOPIC" ]; then
    pkill -f "ntfy_listener.sh" 2>/dev/null || true
    [ ! -f "${PROJECT_DIR}/queue/ntfy_inbox.yaml" ] && echo "inbox:" > "${PROJECT_DIR}/queue/ntfy_inbox.yaml"
    nohup bash "$SCRIPT_DIR/scripts/ntfy_listener.sh" &>/dev/null &
    disown
    log_info "📱 ntfy入力リスナー起動 (topic: $NTFY_TOPIC)"
else
    log_info "📱 ntfy未設定のためリスナーはスキップ"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: 環境確認・完了メッセージ
# ═══════════════════════════════════════════════════════════════════════════════
log_info "🔍 陣容を確認中..."
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📺 Tmux陣容 (Sessions)                                  │"
echo "  └──────────────────────────────────────────────────────────┘"
tmux list-sessions | sed 's/^/     /'
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  📋 布陣図 (Formation)                                   │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "     【${SHOGUN_SESSION}セッション】将軍の本陣"
echo "     ┌─────────────────────────────┐"
echo "     │  Pane 0: 将軍 (SHOGUN)      │  ← 総大将・プロジェクト統括"
echo "     └─────────────────────────────┘"
echo ""
echo "     【${MULTIAGENT_SESSION}セッション】家老・足軽の陣（2x3 = 6ペイン）"
echo "     ┌─────────┬─────────┐"
echo "     │  karo   │ashigaru3│"
echo "     │  (家老) │ (足軽3) │"
echo "     ├─────────┼─────────┤"
echo "     │ashigaru1│ashigaru4│"
echo "     │ (足軽1) │ (足軽4) │"
echo "     ├─────────┼─────────┤"
echo "     │ashigaru2│ashigaru5│"
echo "     │ (足軽2) │ (足軽5) │"
echo "     └─────────┴─────────┘"
echo ""

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║  🏯 出陣準備完了！天下布武！                              ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

if [ "$SETUP_ONLY" = true ]; then
    echo "  ⚠️  セットアップのみモード: Claude Codeは未起動です"
    echo ""
    echo "  手動でClaude Codeを起動するには:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  # 将軍を召喚                                            │"
    echo "  │  tmux send-keys -t ${SHOGUN_SESSION} 'claude --dangerously-skip-permissions' Enter │"
    echo "  │                                                          │"
    echo "  │  # 家老・足軽を一斉召喚                                   │"
    echo "  │  for i in {0..5}; do \\                                   │"
    echo "  │    tmux send-keys -t ${MULTIAGENT_SESSION}:0.\$i \\                   │"
    echo "  │      'claude --dangerously-skip-permissions' Enter       │"
    echo "  │  done                                                    │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
fi

echo "  次のステップ:"
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  将軍の本陣にアタッチして命令を開始:                      │"
echo "  │     tmux attach-session -t ${SHOGUN_SESSION}             │"
echo "  │                                                          │"
echo "  │  家老・足軽の陣を確認する:                                │"
echo "  │     tmux attach-session -t ${MULTIAGENT_SESSION}         │"
echo "  │                                                          │"
echo "  │  ※ 各エージェントは指示書を読み込み済み。                 │"
echo "  │    すぐに命令を開始できます。                             │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo "  ════════════════════════════════════════════════════════════"
echo "   天下布武！勝利を掴め！ (Tenka Fubu! Seize victory!)"
echo "  ════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Windows Terminal でタブを開く（-t オプション時のみ）
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$OPEN_TERMINAL" = true ]; then
    log_info "📺 Windows Terminal でタブを展開中..."

    # Windows Terminal が利用可能か確認
    if command -v wt.exe &> /dev/null; then
        wt.exe -w 0 new-tab wsl.exe -e bash -c "tmux attach-session -t ${SHOGUN_SESSION}" \; new-tab wsl.exe -e bash -c "tmux attach-session -t ${MULTIAGENT_SESSION}"
        log_success "  └─ ターミナルタブ展開完了"
    else
        log_info "  └─ wt.exe が見つかりません。手動でアタッチしてください。"
    fi
    echo ""
fi
