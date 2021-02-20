#!/usr/bin/env sh

# Required parameters
DEVRATING_ORGANIZATION=${DEVRATING_ORGANIZATION:?'DEVRATING_ORGANIZATION variable missing.'}
DEVRATING_KEY=${DEVRATING_KEY:?'DEVRATING_KEY variable missing.'}
BITBUCKET_APP_PASSWORD=${BITBUCKET_APP_PASSWORD:?'BITBUCKET_APP_PASSWORD variable missing.'}
BITBUCKET_CLONE_DIR=${BITBUCKET_CLONE_DIR:?'BITBUCKET_CLONE_DIR variable missing.'}
BITBUCKET_WORKSPACE=${BITBUCKET_WORKSPACE:?'BITBUCKET_WORKSPACE variable missing.'}
BITBUCKET_REPO_SLUG=${BITBUCKET_REPO_SLUG:?'BITBUCKET_REPO_SLUG variable missing.'}
BITBUCKET_BRANCH=${BITBUCKET_BRANCH:?'BITBUCKET_BRANCH variable missing.'}
BASE_BRANCH=${BASE_BRANCH:?'BASE_BRANCH variable missing.'}

# Optional parameters
DEVRATING_REPOSITORY=${DEVRATING_REPOSITORY:-"$BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG"}
MAX_ADDITIONS=${MAX_ADDITIONS:-"4000"}

send_to_devrating()
{
  json=$(devrating serialize diff -t $1 -b $2 -e $3 -l $4 -p $BITBUCKET_CLONE_DIR -o $DEVRATING_ORGANIZATION -n $DEVRATING_REPOSITORY)

  set -x
  curl -i -X POST "https://devrating.net/api/v1/diffs/key" -H "key: ${DEVRATING_KEY}" -H "Content-Type: application/json" --data-raw $json
  set +x
}

analyze_pr()
{
  remainder="$1"
  merged_at="${remainder%% *}"; remainder="${remainder#* }"
  merge_commit="${remainder%% *}"; remainder="${remainder#* }"
  base_commit="${remainder%% *}"; remainder="${remainder#* }"
  head_commit="${remainder%% *}"; remainder="${remainder#* }"
  url="${remainder%% *}";

  first_commit="$merge_commit~"
  second_commit="$merge_commit"

  if [ -z "${merge_commit##$head_commit*}" ] ;then # It's a rebased PR
    first_commit="$base_commit"
    second_commit="$head_commit"
  fi

  stat=$(git diff --shortstat $first_commit..$second_commit)
  stat="${stat#*changed, }"
  additions="${stat%% *}"

  if [ "$MAX_ADDITIONS" -eq "0" ] || [ "$additions" -lt "$MAX_ADDITIONS" ]; then
    send_to_devrating $merged_at $first_commit $second_commit $url
  else
    echo "Skipped a PR with ${additions} additions. (${url})"
  fi
}

request_prs()
{
  merged_after=$(date --date "-2160:00" -I) # -90 days from now

  url_base_branch=$(jq -rn --arg x $BASE_BRANCH '$x|@uri')

  page1=$(curl -u "$BITBUCKET_APP_PASSWORD" \
    "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests?fields=values.merge_commit.date,values.merge_commit.hash,values.destination.commit.hash,values.source.commit.hash,values.links.html.href&q=state%3D%22MERGED%22%20AND%20destination.branch.name~%22${url_base_branch}%22%20AND%20updated_on%3E${merged_after}&sort=-updated_on&pagelen=50&page=1" | \
    jq -c -r '.values | .[] | "\(.merge_commit.date) \(.merge_commit.hash) \(.destination.commit.hash) \(.source.commit.hash) \(.links.html.href)"')

  page2=$(curl -u "$BITBUCKET_APP_PASSWORD" \
    "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests?fields=values.merge_commit.date,values.merge_commit.hash,values.destination.commit.hash,values.source.commit.hash,values.links.html.href&q=state%3D%22MERGED%22%20AND%20destination.branch.name~%22${url_base_branch}%22%20AND%20updated_on%3E${merged_after}&sort=-updated_on&pagelen=50&page=2" | \
    jq -c -r '.values | .[] | "\(.merge_commit.date) \(.merge_commit.hash) \(.destination.commit.hash) \(.source.commit.hash) \(.links.html.href)"')

  prs=$(printf "$page2\n$page1" | sort)

  echo "$prs"

  IFS=$"
"

  for pr in $prs; do
    analyze_pr $pr
  done
}

cd $BITBUCKET_CLONE_DIR

request_prs

url_org=$(jq -rn --arg x $DEVRATING_ORGANIZATION '$x|@uri')
url_repo=$(jq -rn --arg x $DEVRATING_REPOSITORY '$x|@uri')

echo "Visit: https://devrating.net/#/repositories/${url_org}/${url_repo}"