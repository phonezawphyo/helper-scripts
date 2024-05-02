#!/bin/bash

unset -f hs_s3_deploy 2> /dev/null
# Sync local folder to s3.
# Add SoftDelete=yes to old remote files.
# Remove SoftDelete tag from existing remote files.
#
# To customize AWS_PROFILE, prefix AWS_PROFILE=yourprofile before the function call.
# E.g. `AWS_PROFILE=default hs_s3_deploy dist your-s3-bucket`
#
function hs_s3_deploy() {
  # Base directory for local files and bucket name
  local_folder=$1
  bucket=$2
  temp_s3_list="s3_contents.json"
  temp_local_list="local_contents.txt"
  temp_local_exists="local_exists.txt"

  # Check if the directory exists
  if [ -d "$local_folder" ]; then
    # Check if the directory is not empty
    if [ "$(ls -A $local_folder)" ]; then
      # pass
    else
      return 1  # Fail
    fi
  else
    return 1 # Fail
  fi
  
  # Sync local folder to S3
  aws s3 sync $local_folder s3://$bucket

  # Get list of all objects in the S3 bucket
  aws s3api list-objects --bucket $bucket --query 'Contents[].Key' --output json > $temp_s3_list

  # Generate list of all files in the local folder
  find $local_folder -type f | sed "s|$local_folder/||" > $temp_local_list

  # Create a presence marker file for local files
  awk '{print $0 " 1"}' $temp_local_list > $temp_local_exists

  # Read S3 list into an array
  s3_files=()
  while IFS= read -r line; do
      s3_files+=("$line")
  done < <(jq -r '.[]' $temp_s3_list)

  # Process each S3 file in parallel
  printf "%s\n" "${s3_files[@]}" | xargs -P 30 -I {} bash -c '
    key="$1"
    bucket="'$bucket'"
    temp_local_exists="'$temp_local_exists'"
    # Check if file exists locally using the marker file
    if grep -q "^$key 1$" $temp_local_exists; then
        # File exists locally, remove SoftDelete tag if it exists
        echo -e "\033[0;32mPERSIST\033[0m $key"
        aws s3api delete-object-tagging --bucket $bucket --key "$key"
    else
        # File does not exist locally, add SoftDelete tag
        echo -e "\033[0;31mDELETE\033[0m  $key"
        aws s3api put-object-tagging --bucket $bucket --key "$key" --tagging "TagSet=[{Key=SoftDelete,Value=yes}]"
    fi
  ' _ {}

  # Clean up
  rm $temp_s3_list $temp_local_list $temp_local_exists
}
