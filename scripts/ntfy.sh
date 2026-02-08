#!/bin/bash
# ============================================================
# ntfy.sh - multi-agent-shogun 通知スクリプト
# ============================================================
# 使用方法:
#   ./scripts/ntfy.sh <PROJECT_ID> <CMD_ID> <MESSAGE> [urgent]
#
# 例:
#   ./scripts/ntfy.sh myproject cmd_001 "API調査が完了"
#   ./scripts/ntfy.sh myproject cmd_002 "要対応あり" urgent
#
# 必要な環境変数（通知タイプに応じて設定）:
#   ntfy:     NTFY_TOPIC - ntfyトピック名
#   chatwork: CHATWORK_API_TOKEN, CHATWORK_ROOM_ID
# ============================================================

set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# tmuxセッション内でdirenvが効かない場合のフォールバック
if [ -f "$ROOT_DIR/.envrc" ]; then
    eval "$(tr -d '\r' < "$ROOT_DIR/.envrc")"
fi

# 引数チェック
if [ $# -lt 3 ]; then
    echo "Usage: $0 <PROJECT_ID> <CMD_ID> <MESSAGE> [urgent]"
    exit 1
fi

PROJECT_ID="$1"
CMD_ID="$2"
MESSAGE="$3"
URGENT="${4:-normal}"

# 設定ファイル読み込み
SETTINGS_FILE="$ROOT_DIR/config/settings.yaml"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Error: Settings file not found: $SETTINGS_FILE"
    exit 1
fi

# 通知タイプを取得
NOTIFICATION_TYPE=$(grep "^  type:" "$SETTINGS_FILE" 2>/dev/null | awk '{print $2}' || echo "none")

# 通知タイプに応じて処理
case "$NOTIFICATION_TYPE" in
    ntfy)
        # 環境変数チェック
        if [ -z "$NTFY_TOPIC" ]; then
            echo "Error: NTFY_TOPIC environment variable is not set"
            exit 1
        fi

        # タイトルと優先度を設定
        if [ "$URGENT" = "urgent" ]; then
            TITLE="🏯 ${PROJECT_ID} 【要対応】"
            PRIORITY="high"
            TAGS="warning,castle"
        else
            TITLE="🏯 ${PROJECT_ID}"
            PRIORITY="default"
            TAGS="white_check_mark,castle"
        fi

        # ntfy で送信
        curl -s -X POST \
            -H "Title: ${TITLE}" \
            -H "Priority: ${PRIORITY}" \
            -H "Tags: ${TAGS}" \
            -d "${CMD_ID}: ${MESSAGE}" \
            "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null

        echo "ntfy notification sent: ${PROJECT_ID} - ${CMD_ID}"
        ;;

    chatwork)
        # 環境変数チェック
        if [ -z "$CHATWORK_API_TOKEN" ]; then
            echo "Error: CHATWORK_API_TOKEN environment variable is not set"
            exit 1
        fi

        if [ -z "$CHATWORK_ROOM_ID" ]; then
            echo "Error: CHATWORK_ROOM_ID environment variable is not set"
            exit 1
        fi

        ROOM_ID="$CHATWORK_ROOM_ID"

        # メッセージ本文を構築
        if [ "$URGENT" = "urgent" ]; then
            BODY="[info][title]🏯 ${PROJECT_ID} 【要対応】[/title]${CMD_ID}: ${MESSAGE}[/info]"
        else
            BODY="[info][title]🏯 ${PROJECT_ID}[/title]${CMD_ID}: ${MESSAGE}[/info]"
        fi

        # Chatwork API で送信
        curl -s -X POST \
            -H "X-ChatWorkToken: ${CHATWORK_API_TOKEN}" \
            -d "body=${BODY}" \
            "https://api.chatwork.com/v2/rooms/${ROOM_ID}/messages" > /dev/null

        echo "Chatwork notification sent: ${PROJECT_ID} - ${CMD_ID}"
        ;;

    macos)
        # macOSの場合
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if [ "$URGENT" = "urgent" ]; then
                SOUND="Ping"
            else
                SOUND="Glass"
            fi

            osascript -e "display notification \"${CMD_ID}: ${MESSAGE}\" with title \"🏯 ${PROJECT_ID}\" sound name \"${SOUND}\""
            echo "macOS notification sent: ${PROJECT_ID} - ${CMD_ID}"
        else
            echo "Warning: macOS notification type selected but not running on macOS"
        fi
        ;;

    none)
        echo "Notification disabled"
        ;;

    *)
        echo "Unknown notification type: $NOTIFICATION_TYPE"
        exit 1
        ;;
esac
