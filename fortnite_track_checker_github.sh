#!/bin/bash

if ! command -v python3 &> /dev/null; then
    echo "Python3 não encontrado"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "curl não encontrado"
    exit 1
fi

# Configurações da API
API_URL="https://fortnite-api.com/v2/shop"
USER_TOKEN="${USER_TOKEN}"  # Será definido como secret
API_TOKEN="${API_TOKEN}"    # Será definido como secret
MUSIC_LIST_FILE="musicas_fortnite.txt"

# Array para armazenar as músicas a serem monitoradas
declare -a TRACKS_TO_MONITOR

# Função para carregar a lista de músicas do arquivo
load_music_list() {
    if [[ -f "$MUSIC_LIST_FILE" ]]; then
        TRACKS_TO_MONITOR=()
        while IFS= read -r line; do
            # Ignorar linhas vazias e comentários
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                TRACKS_TO_MONITOR+=("$line")
            fi
        done < "$MUSIC_LIST_FILE"
        echo "$(date): Carregadas ${#TRACKS_TO_MONITOR[@]} músicas para monitoramento"
    else
        echo "$(date): Arquivo $MUSIC_LIST_FILE não encontrado"
        exit 1
    fi
}

# Função para enviar notificação via Pushover
send_notification() {
    local title="$1"
    local message="$2"
    
    if [[ -n "$USER_TOKEN" && -n "$API_TOKEN" ]]; then
        curl -s \
            --form-string "token=$API_TOKEN" \
            --form-string "user=$USER_TOKEN" \
            --form-string "title=$title" \
            --form-string "message=$message" \
            --form-string "priority=0" \
            https://api.pushover.net/1/messages.json > /dev/null
    fi
}

# Função principal para verificar as músicas do Fortnite
check_fortnite_tracks() {
    # Carregar lista de músicas
    if ! load_music_list; then
        echo "Erro ao carregar lista de músicas"
        return 1
    fi
    
    # Fazer requisição à API
    response=$(curl -s "$API_URL")
    
    # Verificar se a requisição foi bem-sucedida
    if [[ $? -ne 0 ]]; then
        send_notification "🚨 Erro Fortnite Checker" "Erro ao acessar a API do Fortnite"
        echo "$(date): Erro ao acessar API"
        return 1
    fi
    
    # Verificar se há dados válidos
    status=$(echo "$response" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('status', 0))")
    
    if [[ "$status" != "200" ]]; then
        send_notification "🚨 Erro Fortnite Checker" "API retornou status: $status"
        echo "$(date): API status: $status"
        return 1
    fi
    
    # Extrair e verificar tracks usando Python
    tracks_found=$(echo "$response" | python3 -c "
import sys, json

data = json.load(sys.stdin)
entries = data.get('data', {}).get('entries', [])

for i, entry in enumerate(entries):
    if 'tracks' in entry:
        for track in entry['tracks']:
            title = track.get('title', '')
            artist = track.get('artist', '')
            full_title = f'{artist} - {title}'
            print(f'{full_title}|{artist}|{title}')
")
    
    # Ativar comparação case-insensitive
    shopt -s nocasematch
    
    # Verificar se algum track corresponde à nossa lista
    found_tracks=()
    found_details=()
    
    while IFS='|' read -r full_title artist title; do
        if [[ -n "$full_title" && "$full_title" != *"Total de entries"* && "$full_title" != *"Entry"* ]]; then
            
            for monitor_track in "${TRACKS_TO_MONITOR[@]}"; do
                # Extrair apenas o nome da música usando sed para pegar após " - " ou " – "
                monitor_song=$(echo "$monitor_track" | sed 's/.* [-–] //')
                
                if [[ "$full_title" == *"$monitor_track"* ]] || [[ "$title" == *"$monitor_song"* ]]; then
                    found_tracks+=("$full_title")
                    found_details+=("$artist - $title")
                    break
                fi
            done
        fi
    done <<< "$tracks_found"
    
    shopt -u nocasematch
    
    # Enviar notificação com resultados
    if [[ ${#found_tracks[@]} -gt 0 ]]; then
        # Criar mensagem com as músicas encontradas
        if [[ ${#found_tracks[@]} -eq 1 ]]; then
            notification_title="Música Encontrada no Fortnite!"
        else
            notification_title="${#found_tracks[@]} Músicas Encontradas no Fortnite!"
        fi
        
        # Juntar as músicas encontradas em uma mensagem
        music_list=$(printf '%s\n' "${found_details[@]}")
        
        # Enviar notificação Pushover
        send_notification "$notification_title" "$music_list"
        
        # Log das músicas encontradas
        echo "$(date): Encontradas ${#found_tracks[@]} músicas: ${found_tracks[*]}"
    else
        echo "$(date): Nenhuma música da lista encontrada na loja"
    fi
}

# Executar verificação
check_fortnite_tracks
