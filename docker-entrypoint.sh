#!/bin/sh

# Where are we going to mount the remote bucket resource in our container.
DEST=${AWS_S3_MOUNT:-/opt/s3fs/bucket}

# Check variables and defaults
if [ -z "${AWS_S3_ACCESS_KEY_ID}" ] && \
    [ -z "${AWS_S3_SECRET_ACCESS_KEY}" ] && \
    [ -z "${AWS_S3_SECRET_ACCESS_KEY_FILE}" ] && \
    [ -z "${AWS_S3_AUTHFILE}" ]; then
    echo "You need to provide some credentials!!"
    exit
fi
if [ -z "${AWS_S3_BUCKET}" ]; then
    echo "No bucket name provided!"
    exit
fi
if [ -z "${AWS_S3_URL}" ]; then
    AWS_S3_URL="https://s3.amazonaws.com"
fi

if [ -n "${AWS_S3_SECRET_ACCESS_KEY_FILE}" ]; then
    # shellcheck disable=SC2229   # We WANT to read the content of the file pointed by the variable!
    AWS_S3_SECRET_ACCESS_KEY=$(read -r "${AWS_S3_SECRET_ACCESS_KEY_FILE}")
fi

# Create or use authorisation file
if [ -z "${AWS_S3_AUTHFILE}" ]; then
    AWS_S3_AUTHFILE=/opt/s3fs/passwd-s3fs
    echo "${AWS_S3_ACCESS_KEY_ID}:${AWS_S3_SECRET_ACCESS_KEY}" > "${AWS_S3_AUTHFILE}"
    chmod 600 ${AWS_S3_AUTHFILE}
fi

# forget about the password once done (this will have proper effects when the
# PASSWORD_FILE-version of the setting is used)
if [ -n "${AWS_S3_SECRET_ACCESS_KEY}" ]; then
    unset AWS_S3_SECRET_ACCESS_KEY
fi

# Create destination directory if it does not exist.
if [ ! -d "$DEST" ]; then
    mkdir -p "$DEST"
fi

GROUP_NAME=$(getent group "${GID}" | cut -d":" -f1)

# Add a group
if [ "$GID" -gt 0 ] && [ -z "${GROUP_NAME}" ]; then
    addgroup -g "$GID" -S "$GID"
    GROUP_NAME=$GID
fi

# Add a user
if [ "$UID" -gt 0 ]; then
    adduser -u "$UID" -D -G "$GROUP_NAME" "$UID"
    RUN_AS=$UID
    chown "$UID:$GID" "$DEST" "${AWS_S3_AUTHFILE}" /opt/s3fs
fi

# Debug options
DEBUG_OPTS=
if [ "$S3FS_DEBUG" = "1" ]; then
    DEBUG_OPTS="-d -d"
fi

# Additional S3FS options
if [ -n "$S3FS_ARGS" ]; then
    S3FS_ARGS="-o $S3FS_ARGS"
fi

# Mount as the requested used.
su - $RUN_AS -c "s3fs ${AWS_S3_BUCKET} ${DEST} $DEBUG_OPTS ${S3FS_ARGS} \
    -o passwd_file=${AWS_S3_AUTHFILE} \
    -o url=${AWS_S3_URL} \
    -o uid=$UID \
    -o gid=$GID"

# s3fs can claim to have a mount even though it didn't succeed.
# Doing an operation actually forces it to detect that and remove the mount.
su - $RUN_AS -c "ls ${DEST}"

if healthcheck.sh; then
    echo "Mounted bucket ${AWS_S3_BUCKET} onto ${DEST}"
    exec "$@"
else
    echo "Mount failure"
fi
