# systemd-run --user --on-active=60 -d ./setupServiceTempl.sh ipfs 100 100 K

targets=("ipfs" "arweave" "swarm" "s3")
loads=("100 100 K" "100 1 M" "100 10 M" "1 100 M")
loadsArweave=("10 100 K" "100 100 K" "10 1 M" "1 10 M")
delay=0



for i in {0..3}; do
    for target in ${targets[@]}; do
        if [ ${target} != "arweave" ]; then
            load=${loads[$i]}
        else
            load=${loadsArweave[$i]}
        fi
        systemd-run --user --on-active="${delay}h 10m" -d ./setupServiceTempl.sh ${target} ${load}
        ((delay++))
    done
done

