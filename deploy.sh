#! /usr/bin/env bash
#set -x

IFS=

input_file=docker-compose.yml
project_name=$(basename `pwd` | sed -E 's/[^a-zA-Z0-9]+//g')
registry=

input_file=${COMPOSE_FILE:-${input_file}}
project_name=${COMPOSE_PROJECT_NAME:-${project_name}}

# read options

while [ -n "$1" ]; do
    case $1 in
        '-c' | '--compose-file')
            shift && input_file="$1" || die
            ;;
        '-p' | '--project-name')
            shift && project_name="$1" || die
            ;;
        '-r' | '--registry')
            shift && registry="$1" || die
            ;;
    esac
    shift
done

if [[ -z $registry ]]; then
    echo registry not specified. please add option -r or --registry  1>&2
    exit 1
fi

output_file_rnd=`openssl rand -base64 12 | fold -w 10 | head -1`
output_file=$(mktemp "/tmp/docker-compose.yml.${output_file_rnd}")

trim() {
    cat - | sed 's/^[ \t]*//' | sed -e 's/[ \t]*$//'
}

final() {
  [[ -s ${output_file} ]] && rm -f "$output_file"
}

trap final EXIT
trap 'trap - EXIT; final; exit -1' INT PIPE TERM

yaml_stack=()
indent=0
while read line; do
    # skip comment line
    if [[ -n $(echo ${line} | grep -e '^#.*') ]] ; then
        continue
    fi
    deepness=`expr "$line" : '^ *'`
    if [[ ${deepness} -gt 0 ]]; then
        if [[ ${indent} -eq 0 ]]; then
            indent=${deepness}
        fi
        deepness=`expr ${deepness} / ${indent}`
    fi
    key=`echo ${line%%:*} | trim`
    value=`echo ${line#*:} | trim`
    item_value=
    if [[ $(echo $line | grep -e '^ *- ') ]]; then
        key=; value=; item_value=`echo ${line#*  - } | trim`
    else
        if [[ ${deepness} -eq 0 ]]; then
            yaml_stack=(${key})
        else
            yaml_stack=(${yaml_stack[@]:0:${deepness}}); yaml_stack+=( $key )
        fi
    fi
    # rewrite
    if [[ ${deepness} -eq 2 ]]; then
        if [[ ${key} = 'build' ]]; then
            # rewrite build to image
            container_tag=${project_name}/${yaml_stack[1]}
            container_registry=${registry}/${project_name}_${yaml_stack[1]}
            docker build --rm -t ${container_tag} .
            docker tag ${container_tag} ${container_registry}
            docker push ${container_registry}
            printf "%`expr ${deepness} \* ${indent}`s" >> $output_file
            printf "image: ${registry}/${project_name}_${yaml_stack[1]}\n" >> $output_file
        elif [[ ${key} = 'container_name' ]]; then
            : # pass
        else
            printf "$line\n" >> $output_file
        fi
    else
        printf "$line\n" >> $output_file
    fi
    #echo "DEBUG d=${deepness} [${yaml_stack[@]}] value=[${value}] item=[${item_value}]"
done < ${input_file}

docker stack deploy -c ${output_file} ${project_name}
