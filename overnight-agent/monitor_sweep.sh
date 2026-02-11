#!/bin/bash
# Monitor sweep workers and system resources

echo "🔍 Sweep Monitor - Watching for memory pressure..."
echo "Sweep ID: 32g71hrl"
echo "View at: https://wandb.ai/aryavolkan-personal/evolve-neuroevolution/sweeps/32g71hrl"
echo ""

while true; do
    clear
    echo "═══════════════════════════════════════════════════════════════"
    echo "🧹 SWEEP STATUS - $(date '+%H:%M:%S')"
    echo "═══════════════════════════════════════════════════════════════"
    
    # Memory and swap
    echo ""
    echo "💾 MEMORY & SWAP:"
    vm_stat | awk '
        /Pages free/ {free=$3}
        /Pages active/ {active=$3}
        /Pages inactive/ {inactive=$3}
        /Pages wired/ {wired=$3}
        /Pages occupied by compressor/ {compressed=$5}
        /Swapins/ {swapins=$2}
        /Swapouts/ {swapouts=$2}
        END {
            page_size=4096
            free_gb=(free*page_size)/(1024^3)
            active_gb=(active*page_size)/(1024^3)
            inactive_gb=(inactive*page_size)/(1024^3)
            wired_gb=(wired*page_size)/(1024^3)
            compressed_gb=(compressed*page_size)/(1024^3)
            
            printf "  Free:       %.2f GB\n", free_gb
            printf "  Active:     %.2f GB\n", active_gb
            printf "  Inactive:   %.2f GB\n", inactive_gb
            printf "  Wired:      %.2f GB\n", wired_gb
            printf "  Compressed: %.2f GB\n", compressed_gb
            printf "  Swapins:    %s\n", swapins
            printf "  Swapouts:   %s\n", swapouts
        }'
    
    # Check for swap file usage
    echo ""
    swap_used=$(sysctl vm.swapusage | awk '{print $7}' | sed 's/M//')
    if (( $(echo "$swap_used > 0" | bc -l 2>/dev/null || echo 0) )); then
        echo "⚠️  SWAP ACTIVE: ${swap_used}M in use"
    else
        echo "✅ No swap in use"
    fi
    
    # Running processes
    echo ""
    echo "🏃 WORKERS:"
    worker_count=$(ps aux | grep -E "overnight_evolve.py" | grep -v grep | wc -l | xargs)
    godot_count=$(ps aux | grep -E "Godot.*--headless" | grep -v grep | wc -l | xargs)
    echo "  Python workers: $worker_count"
    echo "  Godot instances: $godot_count"
    
    # Memory usage by process
    echo ""
    echo "📊 TOP MEMORY USERS:"
    ps aux | grep -E "(Godot|Python|overnight_evolve)" | grep -v grep | awk '{printf "  %-8s %6s %6s %s\n", $2, $3"%", $6/1024"M", $11}' | head -10
    
    # Latest metrics
    echo ""
    echo "📈 LATEST RUNS:"
    for log in sweep_worker*.log; do
        if [ -f "$log" ]; then
            worker_num=$(echo $log | grep -o '[0-9]')
            last_gen=$(tail -50 "$log" 2>/dev/null | grep "Gen [0-9]" | tail -1)
            if [ -n "$last_gen" ]; then
                echo "  Worker $worker_num: $last_gen"
            fi
        fi
    done
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Press Ctrl+C to stop monitoring"
    
    sleep 10
done
