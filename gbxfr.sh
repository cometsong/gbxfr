#!/usr/bin/env bash
version=0.9.3
version_text="Globus Xfr Script for Batch and Files v$version"

prog_name=${0##*/}
options="h q v V D" # the basics...
options+="c: n: s: p: t: d: b: B o f: " # app specifics
help_text="Usage: $prog_name [-hqvV] [-c <config_file>] -n xfr_label #((see below for other options))

  ${version_text}

        --------------------------------------------------------------------
**NOTE: This script ONLY tested using BATCH mode! Other modes still pending.
            Patience is a virtue. ... and a word that begins with 'P'.
        --------------------------------------------------------------------

    -c configfile Path to config file, setting at least required variables.
                  (See template config file as example.)

  To override config file, or to run immediately:
    -n xfr_label  Transfer job name to show in task list

    -s source_ep  Source endpoint id  (required)
    -p file_path  Source file path  (required, must be abspath)
    -t target_ep  Target endpoint id  (required)
    -d dest_path  Destination path  (default '/~/')
    -B            Use basename of local file to place in dest_path.

    -b batch_file Path to batch file
                  Sets 'batch' transfer mode; note that -p and -d are
                  used to prepend to relative paths in batch_file.
    -o            Reuse/overwrite batch file using file_glob
    -f file_glob  Glob(s) of files to place into batch_file.
                  (default '*' within source '-p' file_path)
                  NOTE: Will create or OVERWRITE batch_file!

    -h         Display this help text and exit
    -q         Quiet
    -V         Display version information and exit
"

#TODO: -v         Verbose mode
#TODO: -w         Wait for task to complete. (default: no)
#TODO: -r         Recursive IF full directories and no batch file or globs!

#TODO: --jq format: determine Globus specs for diff commands
#  --jq, --jmespath 'EXPR'
#    Supply a JMESPath expression to apply to json output. Takes precedence over any specified '--format' and forces the format to be json processed by this expression.
#    A full specification of the JMESPath language for querying JSON structures may be found at https://jmespath.org/
#
# globus endpoint search --filter-scope my-endpoints \
#   --jq "DATA[].{data_type:DATA_TYPE,
#                 Display_name:display_name,
#                 description:description,
#                 host_endpoint:host_endpoint,
#                 host_point_id:host_point_id,
#                 is_globus_connect:is_globus_connect,
#                 ID:id,
#                 department:department,
#                 Default_directory:default_directory}"
#
#  --jq "DATA[].{bookmark_name:name, endpoint_id:endpoint_id, id:id, path:path}"

main() {
  ### GLOBUS vars defaults: ###
  xfr_label=        #default empty
  source_ep=''      #required
  file_path=''      #required, abspath
  target_ep=''      #required
  dest_path='/~/'
  dest_base=0       #use file's basename in dest_path/filename

  batch_file=       #default empty
  batch_file_reuse= #default false
  file_glob='*'

  #task_wait=0
  #xfr_mode=
  notifications='--notify failed,inactive'

  #xfr=( #TODO: use array instead?
  #  xfr_label
  #  source_ep file_path file_glob
  #  target_ep dest_path
  #  batch_file xfr_mode
  #  #.....
  #)

  ### //end// GLOBUS vars ###

  ### start main actions ###
  set_defaults # char vars, traps
  parse_options "$@"
  [ $# == 0 ] && opt_V=true; # show version when run with no args
  shift $((OPTIND-1))

  # shellcheck disable=2154
  {
    $opt_h && usage;
    $opt_V && version;
    $opt_q && info() { :; }
    [ "$opt_D" ] || debug() { :; } # NB debug not in help_text

    # base config setup:
    $opt_c && xfr_config="$val_c";

    # xfr option overrides?
    $opt_n && xfr_label="$val_n";
    $opt_s && source_ep="$val_s";
    $opt_p && file_path="$val_p";
    $opt_t && target_ep="$val_t";
    $opt_d && dest_path="$val_d";
    $opt_B && dest_base="$val_B";

    $opt_b && batch_file="$val_b";
    $opt_o && batch_file_reuse=1;
    $opt_f && file_glob="$val_f";

    #TODO: other options...
    #$opt_w && task_wait="$val_w";
    # [ $opt_r \
    #   && -n "$batch_file" && -n "$file_glob" ] \
    #   && xfr_mode='--recursive'
  }

  if [ $opt_c ]; then
    if [ -r "${xfr_config}" ]; then #TODO: test run w/o config file
      load_config "$xfr_config";
    else
      info "Specified config file '$xfr_config' is not readable."
    fi
  fi

  [ $xfr_label ] \
    && xfr_label="${xfr_label}-$(get_datestamp "%Y%m%d")" \
    || xfr_label="gbxfr-$(get_datestamp "%Y%m%d")"

  check_var_values

  endpoint_activate $source_ep $target_ep

  if [ -n "$batch_file" ]; then
    if [ "$batch_file_reuse" == 1 ]; then
      info "Rewriting batch file '$batch_file' using '$file_glob'"
      debug "Config variable 'batch_file' has value '$batch_file'"
      debug "Config variable 'file_glob' has value '$file_glob'"
      create_batch_file_with_paths $batch_file "'$file_glob'"
    fi
    globus_xfr_batch
  else
    info "Pending work on single-file or recursive globus transfers."
    # globus_xfr_submit
  fi

      #TODO: ¿¿¿ implement this for runs using '-B' W/O specifying batch_file name ???
      #[ -z "$batch_file" ] && [ $batch_file_reuse ] \
      #  || { batch_file=$(mktemp -t ${xfr_label}) \
      #      || info "Had trouble making batch_file." } \
      #  || batch_file=${xfr_label}_batch.fof

}

load_config() {
  info "Getting configuration parameters from file '$1'"
  _envvars_regex='^([[:alpha:]][_[:alnum:]][^=]+)=([^#]*).*$' # regex needs bash!
  while read -r cfg; do #TODO: ? for more verbose config reads....
    if [[ $cfg =~ $_envvars_regex ]]; then
      var="${BASH_REMATCH[1]}";
      val="${BASH_REMATCH[2]}";
      debug "config var: $var, val: $val"
      eval "$var=$val"
    fi
  done < "$1"
}

check_var_values() {
  for var in source_ep target_ep file_path ; do
    val=$(get_val $var);
    [ -n "$val" ] \
      && info "Config variable '$var' has value '$val'" \
      || error 2 "Variable '$var' needs to have a value!"
  done

  #FIXME: check_var_values fp_orig presumes local path! check only for valid path chars?
  #fp_orig=${file_path} && \
  #file_path=$(realpath ${file_path//\'/}) \
  #  || error 2 "Config variable 'file_path'=>'$fp_orig' can't be resolved!"
  #debug "Config variable 'file_path' has realpath '$file_path'"

  ### check val formats #TODO: check variable formats regex...
  alphanums=( source_ep target_ep )
  for var in ${alphanums[*]}; do
    val=$(get_val $var);
    [[ $val =~ ^[-[:alnum:]]{36}$ ]] \
      || error 2 "$var must be 36 alphanumeric and hyphen characters.";
  done

}

create_batch_file_with_paths() {
  _File=${1?What file?}; shift;
  _File=$(realpath $_File)
  _Glob="${*:-*}"
  _Glob="${_Glob//\'/}" # remove any single quotes

  truncate -s0 $_File && \
  cd $file_path && \
  for _F in ${_Glob[*]} ; do
    if [ -f "$_F" ]; then
      _F2=${_F}
      [ "$dest_base" = 1 ] && _F2=$(basename "$_F")
      _Fsrc="${file_path}/${_F}"
      _Fdst="${dest_path}/${_F2}"
    fi
    printf "%s %s\n" "$_Fsrc" "$_Fdst";
  done >> $_File
  unset _File _Glob _Fdst _Fsrc _F _F2
  cd - >/dev/null
}

endpoint_activate() {
  # expects arg(s) as endpoint UUID codes; prints results
  for ep_id in ${*}; do
    ep_active="$(globus endpoint is-activated "$ep_id")"
    if [ $? -eq 1 ]; then
      ep_activate="globus endpoint activate --force $ep_id"
      info "Executing '$ep_activate'"
      info "$(eval "$ep_activate")"
    fi
  done
}

globus_xfr_batch() {
  info "Initiating batch globus transfer: '${xfr_label}'"
  globus transfer           \
    --label $xfr_label      \
    ${notifications}        \
    --no-verify-checksum    \
    -s checksum             \
    --jmespath 'task_id'    \
    $source_ep              \
    $target_ep              \
    --batch < ${batch_file} \
    > ${xfr_label}.task_id.json
}

globus_xfr() {
  info "Initiating globus transfer: '${xfr_label}'"
  globus transfer         \
    --label $xfr_label    \
    ${notifications}      \
    --no-verify-checksum  \
    -s checksum           \
    --jmespath 'task_id'  \
    $source_ep:$file_path \
    $target_ep:$dest_path \
    > ${xfr_label}.task_id.json
}

globus_task_wait() {
  task_id=${1}
  info "Waiting on globus task '$task_id'"
  globus task wait \
    --timeout 'N'  \
    --heartbeat    \
    ['OPTIONS']    \
    "$task_id"
}


#------------------------------------------------------------------------------#
# Generics
#------------------------------------------------------------------------------#
get_val()(eval "echo \$${1}") #$1=var_name

# shellcheck disable=2034,2046
set_defaults() {
  set -e
  trap 'clean_exit' EXIT TERM
  trap 'clean_exit HUP' HUP
  trap 'clean_exit INT' INT
  IFS=' '
  set -- $(printf '\n \r \t \033')
  nl=$1 cr=$2 tab=$3 esc=$4
  IFS=\ $tab
}

# For a given optstring, this function sets the variables
# "opt_<optchar>" to true/false and val_<optchar> to its value.
parse_options() {
  for _opt in $options; do
    # The POSIX spec does not say anything about spaces in the
    # optstring, so lets get rid of them.
    _optstring=$_optstring$_opt
    eval "opt_${_opt%:}=false"
  done

  while getopts ":$_optstring" _opt; do
    case $_opt in
      :) usage "option '$OPTARG' requires a value" ;;
      \?) usage "unrecognized option '$OPTARG'" ;;
      *)
        eval "opt_$_opt=true"
        [ -n "$OPTARG" ] &&
          eval "val_$_opt=\$OPTARG"
      ;;
    esac
  done
  unset _opt _optstring OPTARG
}

trim_char() { # trim off surrounding 'char's e.g. quotes
    _char=$1 && shift;
    _var=$*;
    _var="${_var#"${_var%%[!${_char}]*}"}";  # remove leading
    _var="${_var%"${_var##*[!${_char}]}"}";  # remove trailing
    printf "$var";
    unset _var _char
}
trim_spaces(){ echo $(trim_char '[:space:]' "$*"); } # trim off surrounding 'char's = [:space:]
trim_spaces(){ echo $(trim_char "[:space:]" $*); } # trim off surrounding 'char's = [:space:]
trim_spaces()(trim_char '[:space:]' $*) # trim off surrounding 'char's = [:space:]

get_datestamp() {
  _format=${*:-"%Y%m%d"};
  echo $(date +"$_format");
}
get_timestamp()(get_datestamp %Y%m%d_%H%M%S%Z)

info()    { printf '%b\n' "$*"; }
debug()   { info 'DEBUG: ' "$*" >&2; }
version() { info "$version_text"; exit; }

error() {
  _error=${1:-1}; shift;
  printf '%s %s %s\n' "$prog_name" "Error:" "$*" >&2;
  exit "$_error";
}

usage() {
  [ $# -ne 0 ] && {
    exec >&2;
    printf '%s: %s\n\n' "$prog_name" "$*";
  }
  printf %s\\n "$help_text"
  exit ${1:+1}
}

clean_exit() {
  _exit_status=$?
  trap - EXIT

  [ $# -ne 0 ] && {
    trap - "$1"
    kill -s "$1" -$$
  }
  exit "$_exit_status"
}

main "$@"

# vim: set ts=2 sw=0 tw=100:
