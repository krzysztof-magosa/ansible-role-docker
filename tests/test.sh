#!/bin/bash

# Set defaults so script can be used manually as well.
distribution="${distribution:-centos}"
version="${version:-7}"
ansible_version="2.6.3"

# Variables
role="docker"
docker_file="tests/docker/${distribution}-${version}"
docker_tag="${distribution}-${version}:ansible-${ansible_version}"
role_path="/etc/ansible/roles/${role}"
out2=$(mktemp)

# Preparation of docker image
set -e
docker pull ${distribution}:${version}
docker build --file=${docker_file} --tag=${docker_tag} --build-arg ansible=${ansible_version} .
docker_id=$(docker run --detach --privileged -v /sys/fs/cgroup:/sys/fs/cgroup:ro --volume=${PWD}:${role_path}:ro ${docker_tag})
set +e

# First run
echo "First run..."
docker exec ${docker_id} env ANSIBLE_FORCE_COLOR=1 ansible-playbook ${role_path}/tests/test.yml -i ${role_path}/tests/inventory
rc1=$?

# Second run
echo "Second run..."
docker exec ${docker_id} env ANSIBLE_FORCE_COLOR=1 ANSIBLE_STDOUT_CALLBACK=actionable ansible-playbook ${role_path}/tests/test.yml -i ${role_path}/tests/inventory | tee ${out2}
rc2=$?

# Check if second run applied any changes
grep -qE 'changed=[1-9]+' ${out2}
changed=$?

# Display summary
echo "1st run:     $([ ${rc1} -eq 0 ] && echo 'OK' || echo 'FAILED')"
echo "2nd run:     $([ ${rc2} -eq 0 ] && echo 'OK' || echo 'FAILED')"
echo "Idempotence: $([ ${changed} -ne 0 ] && echo 'OK' || echo 'FAILED')"

# Cleanup
rm -f ${out2}
docker rm -f ${docker_id}

# Both runs must be fine, with idempotency preserved.
[ ${rc1} -eq 0 -a ${rc2} -eq 0 -a ${changed} -ne 0 ] && exit 0 || exit 1
