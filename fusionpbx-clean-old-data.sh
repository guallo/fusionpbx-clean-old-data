#!/usr/bin/env bash

# Based on:
#   - https://github.com/fusionpbx/fusionpbx-install.sh/blob/d24a68080c4c51e839728e6d9ac34f44f68f096c/debian/resources/backup/fusionpbx-maintenance

# Tested on:
#   - FusionPBX 4.5.14 https://github.com/fusionpbx/fusionpbx/tree/2c7753c471ac93ca78ccbaf6acf9960ebf77ab0b
#   - freeswitch 1.10.3~release~15~129de34d84~buster-1~buster+1
#   - Debian GNU/Linux 10 (buster)

if [ -z "${BASH+x}" ]; then
    echo "error: it must be run by shell 'bash'" >&2
    exit 1
fi

# Uncomment below to avoid asking password for database username 'fusionpbx':
#PGPASSWORD="put the password between these quotes"

DAYS_REGEX='\s*\d+\s*'

DOMAIN_REGEX='[a-zA-Z0-9-.]+'
DOMAIN_LIST_REGEX="\\s*$DOMAIN_REGEX(\\s*,\\s*$DOMAIN_REGEX)*\\s*"
DOMAIN_ALL_REGEX='\s*all\s*'

PSQL() {
    PGPASSWORD="$PGPASSWORD" \
        psql -P pager -h localhost -d fusionpbx -U fusionpbx -w "$@"
}

load_values() {
    __VALUES__=()
    
    while IFS= read -r row_line; do
        while IFS= read -r value_line; do
            read -r value <<< "$value_line"
            __VALUES__[${#__VALUES__[@]}]="$value"
        done < <(grep -Po '[^|]+' <<< "$row_line")
    done < <(echo -n "$1" | grep -P '.' | tail -n +3 | head -n -1)
}

domain_condition() {
    local in_="$1"  # '1' or '0'
    local domains="$2"  # 'some.domain.com, another.domain'
    local domain_name_field="$3"  # 'd.domain_name'
    local domain_condition
    
    if grep -qP "$DOMAIN_LIST_REGEX" <<< "$domains"; then
        local not
        local quoted_domains
        
        not=$(! (( $in_ )) && echo not)
        quoted_domains=$(sed 's/\([^, ]\+\)/'"'"'\1'"'"'/g' <<< "$domains")
        domain_condition="$domain_name_field $not in ($quoted_domains)"
    elif (( $in_ )); then
        domain_condition='1 = 0'
    else
        domain_condition='1 = 1'
    fi
    
    echo "$domain_condition"
}

clean_recordings_and_cdr() {
    local in_="$1"  # '1' or '0'
    local domains="$2"  # 'some.domain.com, another.domain'
    local after_days="$3"  # e.g. '90'
    
    local domain_condition_=$(domain_condition "$in_" "$domains" 'd.domain_name')
    
    # recordings' tables
    
    local query="
        select 
            cr.call_recording_path || '/' || cr.call_recording_name 
        from 
            v_call_recordings cr, 
            v_domains d 
        where 
            cr.domain_uuid = d.domain_uuid and 
            $domain_condition_ and 
            cr.call_recording_date <= now() - interval '$after_days days' and 
            cr.call_recording_path is not null and 
            cr.call_recording_name is not null
    "
    local recordings_results
    recordings_results=$(PSQL -c "$query")
    (( $? )) && return 2
    
    local stmt="
        delete from 
            v_call_recordings cr using 
            v_domains d 
        where 
            cr.domain_uuid = d.domain_uuid and
            $domain_condition_ and
            cr.call_recording_date <= now() - interval '$after_days days'
    "
    PSQL -c "$stmt"
    (( $? )) && return 2
    
    # cdr's tables
    
    query="
        select 
            cdr.record_path || '/' || cdr.record_name 
        from 
            v_xml_cdr cdr, 
            v_domains d 
        where 
            cdr.domain_uuid = d.domain_uuid and 
            $domain_condition_ and 
            cdr.start_stamp <= now() - interval '$after_days days' and 
            cdr.record_path is not null and 
            cdr.record_name is not null
    "
    local cdr_results
    cdr_results=$(PSQL -c "$query")
    (( $? )) && return 2
    
    stmt="
        delete from 
            v_xml_cdr cdr using 
            v_domains d 
        where 
            cdr.domain_uuid = d.domain_uuid and
            $domain_condition_ and
            cdr.start_stamp <= now() - interval '$after_days days'
    "
    PSQL -c "$stmt"
    (( $? )) && return 2
    
    # recordings' files
    
    local i
    load_values "$recordings_results"
    
    for i in $(seq ${#__VALUES__[@]}); do
        rm -f "${__VALUES__[$((i - 1))]}"
    done
    
    # cdr's files
    
    load_values "$cdr_results"
    
    for i in $(seq ${#__VALUES__[@]}); do
        rm -f "${__VALUES__[$((i - 1))]}"
    done
}

clean_fax() {
    local in_="$1"  # '1' or '0'
    local domains="$2"  # 'some.domain.com, another.domain'
    local after_days="$3"  # e.g. '90'
    
    local domain_condition_=$(domain_condition "$in_" "$domains" 'd.domain_name')
    
    local query="
        select 
            ff.fax_file_path 
        from 
            v_fax_files ff, 
            v_domains d 
        where 
            ff.domain_uuid = d.domain_uuid and 
            $domain_condition_ and 
            ff.fax_date <= now() - interval '$after_days days' and 
            ff.fax_file_path is not null
    "
    local results
    results=$(PSQL -c "$query")
    (( $? )) && return 2
    load_values "$results"
    
    local stmt="
        delete from 
            v_fax_files ff using 
            v_domains d 
        where 
            ff.domain_uuid = d.domain_uuid and
            $domain_condition_ and
            ff.fax_date <= now() - interval '$after_days days'
    "
    PSQL -c "$stmt"
    (( $? )) && return 2
    
    local i
    
    for i in $(seq ${#__VALUES__[@]}); do
        rm -f "${__VALUES__[$((i - 1))]}"
    done
    
    stmt="
        delete from 
            v_fax_logs fl using 
            v_domains d 
        where 
            fl.domain_uuid = d.domain_uuid and
            $domain_condition_ and
            fl.fax_date <= now() - interval '$after_days days'
    "
    PSQL -c "$stmt"
    (( $? )) && return 2
}

clean_voicemail_messages() {
    local in_="$1"  # '1' or '0'
    local domains="$2"  # 'some.domain.com, another.domain'
    local after_days="$3"  # e.g. '90'
    
    local domain_condition_=$(domain_condition "$in_" "$domains" 'd.domain_name')
    
    local query="
        select 
            '/var/lib/freeswitch/storage/voicemail/default/' || 
                d.domain_name || '/' || vm.voicemail_id, 
            msg.voicemail_message_uuid 
        from 
            v_voicemails vm, 
            v_voicemail_messages msg, 
            v_domains d 
        where 
            vm.voicemail_uuid = msg.voicemail_uuid and 
            msg.domain_uuid = d.domain_uuid and 
            $domain_condition_ and 
            to_timestamp(msg.created_epoch) <= now() - interval '$after_days days' and 
            vm.voicemail_id is not null
    "
    local results
    results=$(PSQL -c "$query")
    (( $? )) && return 2
    load_values "$results"
    
    local stmt="
        delete from 
            v_voicemail_messages msg using 
            v_domains d 
        where 
            msg.domain_uuid = d.domain_uuid and
            $domain_condition_ and
            to_timestamp(msg.created_epoch) <= now() - interval '$after_days days'
    "
    PSQL -c "$stmt"
    (( $? )) && return 2
    
    local i
    
    for i in $(seq 1 2 ${#__VALUES__[@]}); do
        rm -f "${__VALUES__[$((i - 1))]}/"*"${__VALUES__[$i]}"*
    done
}

clean_logs() {
    local after_days="$1"  # e.g. '90'
    
    find /var/log/freeswitch/ -maxdepth 1 -type f -name 'freeswitch.log.*' \
        -mtime +$(($after_days - 1)) -exec rm -f '{}' ';'
}

is_all() {
    local domains="$1"
    
    grep -qP "^$DOMAIN_ALL_REGEX$" <<< "$domains"
}

validate_user() {
    local expected_user="$1"
    
    if [ "$(id -u)" != "$(id -u "$expected_user")" ]; then
        expected_user_error "$expected_user"
        return 1
    fi
    
    return 0
}

validate_days() {
    local days="$1"
    
    [ $(wc -l <<< "$days") -eq 1 ] || return 1
    grep -qP "^$DAYS_REGEX$" <<< "$days" || return 2
    return 0
}

validate_domains() {
    local domains="$1"
    local enable_kw_all="$2"  # '1' or '0'
    
    [ $(wc -l <<< "$domains") -eq 1 ] || return 1
    
    if (( $enable_kw_all )) && is_all "$domains"; then
        return 0;
    fi
    
    grep -qP "^$DOMAIN_LIST_REGEX$" <<< "$domains" || return 2
    
    local results
    results=$(PSQL -c 'select domain_name from v_domains')
    (( $? )) && return 3
    load_values "$results"
    
    local domain
    
    for domain in $(grep -Po "$DOMAIN_REGEX" <<< "$domains"); do
        local found=0
        local existing_domain
        
        for existing_domain in "${__VALUES__[@]}"; do
            if [ "$domain" = "$existing_domain" ]; then
                found=1
                break
            fi
        done
        
        if ! (( $found )); then
            echo "$domain"
            return 4
        fi
    done
    
    return 0
}

validate_exclude() {
    local domains="$1"
    
    validate_domains "$domains" '0'
}

validate_cross() {
    [ -n "${p_days+x}" ] || return 1
    [ -n "${p_domains+x}" ] || return 2
    [ -z "${p_exclude+x}" ] || is_all "$p_domains" || return 3
    return 0
}

see_usage() {
    local usage="\
usage:
    $ sudo -H -u www-data bash $BASH_SOURCE \\
                                    --days <mininum-age-of-data> \\
                                    --domains <all|comma-separated-list> \\
                                    [--exclude <comma-separated-list>]
    where:
        --days      is the minimum age (in days) the data must has to be cleaned
        --domains   a comma separated list of domains to be cleaned 
                    (e.g 'some.domain.com, another.domain') or the keyword 'all'
                    to select all available domains
        --exclude   can only be used when --domains is 'all' to exclude a comma 
                    separated list of domains of been cleaned";
    
    echo "see below for correct usage:" >&2
    echo "$usage" >&2
}

expected_user_error() {
    local expected_user="$1"
    
    echo "error: it must be run by user '$expected_user'" >&2
    see_usage
}

missing_value_error() {
    local parameter="$1"
    
    echo "error: missing value for parameter '$parameter'" >&2
    see_usage
}

invalid_value_error() {
    local parameter="$1"
    local value="$2"
    
    echo "error: invalid value '$value' for parameter '$parameter'" >&2
    see_usage
}

database_error() {
    echo "error: there was a database related issue" >&2
}

non_existing_domain_error() {
    local domain="$1"
    
    echo "error: domain '$domain' does not exist in database" >&2
}

unsupported_parameter_error() {
    local parameter="$1"
    
    echo "error: unsupported parameter '$parameter'" >&2
    see_usage
}

cross_validation_error() {
    echo "error: cross validation failed" >&2
    see_usage
}

parse_command_line() {
    while (( $# )); do
        case "$1" in
            --days)
                if [ $# -lt 2 ]; then
                    missing_value_error "$1"
                    return 1
                fi
                
                validate_days "$2"
                
                if (( $? )); then
                    invalid_value_error "$1" "$2"
                    return 1
                fi
                
                p_days="$2"
                shift 2
                ;;
            --domains)
                if [ $# -lt 2 ]; then
                    missing_value_error "$1"
                    return 1
                fi
                
                local output
                output=$(validate_domains "$2" '1')
                
                case $? in
                    0)
                        p_domains="$2"
                        shift 2
                        ;;
                    3)
                        database_error
                        return 2
                        ;;
                    4)
                        non_existing_domain_error "$output"
                        return 3
                        ;;
                    *)
                        invalid_value_error "$1" "$2"
                        return 1
                        ;;
                esac
                ;;
            --exclude)
                if [ $# -lt 2 ]; then
                    missing_value_error "$1"
                    return 1
                fi
                
                local output
                output=$(validate_exclude "$2")
                
                case $? in
                    0)
                        p_exclude="$2"
                        shift 2
                        ;;
                    3)
                        database_error
                        return 2
                        ;;
                    4)
                        non_existing_domain_error "$output"
                        return 3
                        ;;
                    *)
                        invalid_value_error "$1" "$2"
                        return 1
                        ;;
                esac
                ;;
            *)
                unsupported_parameter_error "$1"
                return 1
                ;;
        esac
    done
    
    validate_cross
    
    if (( $? )); then
        cross_validation_error
        return 1
    fi
    
    return 0
}

clean_domains() {
    local domains="$1"
    
    domains=$(sed 's/\s*,\s*/, /g' <<< "$domains")
    domains=$(sed 's/^\s*//' <<< "$domains")
    domains=$(sed 's/\s*$//' <<< "$domains")
    
    echo "$domains"
}

clean_p_days() {
    p_days=$(sed 's/^\s*//' <<< "$p_days")
    p_days=$(sed 's/\s*$//' <<< "$p_days")
}

clean_p_domains() {
    p_domains=$(clean_domains "$p_domains")
}

clean_p_exclude() {
    p_exclude=$(clean_domains "$p_exclude")
}

clean_command_line() {
    clean_p_days
    clean_p_domains
    [ -n "${p_exclude+x}" ] && clean_p_exclude
}

main() {
    validate_user 'www-data' || return 2
    
    if [ -z "${PGPASSWORD+x}" ]; then
        echo -n "Password for database username 'fusionpbx': "
        IFS= read -rs PGPASSWORD
        echo
    fi
    
    parse_command_line "$@"
    
    ! (( $? )) || return 3
    
    clean_command_line
    
    local in_
    local domains
    local after_days
    
    if [ -n "${p_exclude+x}" ]; then
        in_=0
        domains="$p_exclude"
        after_days=$p_days
    elif is_all "$p_domains"; then
        in_=0
        domains=''
        after_days=$p_days
    else
        in_=1
        domains="$p_domains"
        after_days=$p_days
    fi
    
    local failed=0
    
    clean_recordings_and_cdr "$in_" "$domains" "$after_days"
    ! (( $? )) || failed=1
    clean_fax "$in_" "$domains" "$after_days"
    ! (( $? )) || failed=1
    clean_voicemail_messages "$in_" "$domains" "$after_days"
    ! (( $? )) || failed=1
    clean_logs "$after_days"
    ! (( $? )) || failed=1
    
    ! (( $failed )) && return 0 || return 4
}

main "$@"
