#!/bin/sh

default_timer_dir="${XDG_DATA_HOME:-$HOME/.local/share}/timers"

timer_dir="${TIMER_DIR:-$default_timer_dir}"

mkdir -p "$timer_dir"

display_timer() {
  timer_id=$1
  hours=$2
  minutes=$3
  seconds=$4
  printf "Timer %s: %d:%02d:%02d\n" "$timer_id" "$hours" "$minutes" "$seconds"
}

save_timer_state() {
  timer_id=$1
  duration=$2
  event=$3
  if [ "$event" = "D" ]; then
    echo "$event $duration" > "$timer_dir/timer_$timer_id.txt"
  else
    echo "$event $duration" >> "$timer_dir/timer_$timer_id.txt"
  fi
}

load_timer_state() {
  timer_id=$1
  if [ -f "$timer_dir/timer_$timer_id.txt" ]; then
    head -n 1 "$timer_dir/timer_$timer_id.txt" | cut -d ' ' -f 2
  else
    echo "0"
  fi
}

get_last_event() {
  timer_id=$1
  if [ -f "$timer_dir/timer_$timer_id.txt" ]; then
    tail -n 1 "$timer_dir/timer_$timer_id.txt" | cut -d ' ' -f 1
  else
    echo "S"
  fi
}

find_unused_timer_id() {
  timer_id=0
  while [ -f "$timer_dir/timer_$timer_id.txt" ]; do
    timer_id=$((timer_id + 1))
  done
  printf "%d\n" "$timer_id"
}

parse_time_input() {
  time_input=$1
  IFS=':' read -r hours minutes seconds << EOF
$time_input
EOF
  case $time_input in
    *:*:*)
      # HH:MM:SS format
      ;;
    *:*)
      # MM:SS format
      seconds=$minutes
      minutes=$hours
      hours=0
      ;;
    *)
      # SS format
      hours=0
      minutes=0
      seconds=$time_input
      ;;
  esac
  total_seconds=$((${hours:-0} * 3600 + ${minutes:-0} * 60 + ${seconds:-0}))
}

calculate_remaining_time() {
  timer_id=$1
  invert=$2
  duration=$(load_timer_state "$timer_id")
  remaining_time=$duration

  start_time=0
  while IFS= read -r line; do
    event=${line%% *}
    timestamp=${line#* }
    case $event in
      S)
        if [ $start_time -ne 0 ]; then
          remaining_time=$((remaining_time - (timestamp - start_time)))
        fi
        start_time=$timestamp
        ;;
      P)
        remaining_time=$((remaining_time - (timestamp - start_time)))
        start_time=0
        ;;
    esac
  done < "$timer_dir/timer_$timer_id.txt"

  if [ $invert -ne 1 ]; then
	  if [ $start_time -ne 0 ]; then
	    current_time=$(date +%s)
	    remaining_time=$((remaining_time - (current_time - start_time)))
	  fi
  else
	  if [ $start_time -ne 0 ]; then
	    current_time=$(date +%s)
	    remaining_time=$((remaining_time - (current_time - start_time)))
	  fi
	    remaining_time=$((duration - remaining_time))
  fi


  if [ $remaining_time -lt 0 ]; then
    remaining_time=0
  fi

  hours=$((remaining_time / 3600))
  minutes=$((remaining_time % 3600 / 60))
  seconds=$((remaining_time % 60))
}

command=$1
shift

case $command in
  new)
    timer_id=$(find_unused_timer_id)
    total_seconds=0

    while [ $# -gt 0 ]; do
      case $1 in
        *:*)
          parse_time_input "$1"
          total_seconds=$((${hours:-0} * 3600 + ${minutes:-0} * 60 + ${seconds:-0}))
          shift
          ;;
        *)
          echo "Invalid argument: $1"
          exit 1
          ;;
      esac
    done

    start_time=$(date +%s)
    save_timer_state "$timer_id" "$total_seconds" "D"
    save_timer_state "$timer_id" "$start_time" "S"
    echo "New timer created with ID: $timer_id"
    ;;
  *)
    timer_id=$command
    if ! [ -f "$timer_dir/timer_$timer_id.txt" ]; then
      echo "Timer with ID $timer_id does not exist."
      exit 1
    fi

    command=$1
    shift

    case $command in
      start)
        last_event=$(get_last_event "$timer_id")
        if [ "$last_event" = "P" ]; then
          start_time=$(date +%s)
          save_timer_state "$timer_id" "$start_time" "S"
          echo "Timer $timer_id resumed."
        else
          echo "Timer $timer_id is already running."
        fi
        ;;
      stop)
        last_event=$(get_last_event "$timer_id")
        if [ "$last_event" = "S" ]; then
          pause_time=$(date +%s)
          save_timer_state "$timer_id" "$pause_time" "P"
          echo "Timer $timer_id stopped."
        else
          echo "Timer $timer_id is already stopped."
        fi
        ;;
      delete)
        rm -f "$timer_dir/timer_$timer_id.txt"
        echo "Timer $timer_id deleted."
        ;;
      pause)
        last_event=$(get_last_event "$timer_id")
        if [ "$last_event" = "S" ]; then
          pause_time=$(date +%s)
          save_timer_state "$timer_id" "$pause_time" "P"
          echo "Timer $timer_id paused."
        else
          echo "Timer $timer_id is already paused."
        fi
        ;;
      status)
	invert=0
	      case $1 in
		-u|--up)
			invert=1
		  shift 
		  ;;
		-d|--down)
			invert=0
		  shift 
		  ;;
	      esac
        last_event=$(get_last_event "$timer_id")
        case $last_event in
          S)
            status="Running"
            ;;
          P)
            status="Paused"
            ;;
          *)
            status="Stopped"
            ;;
        esac
        calculate_remaining_time "$timer_id" "$invert"
        display_timer "$timer_id" "$hours" "$minutes" "$seconds"
        echo "Status: $status"
        ;;
      *)
        echo "Usage: $0 <command> [timer_id] [options]"
        echo "Commands:"
        echo "  new [options]  : Create a new timer and automatically choose id"
        echo "  start          : Start/resume the timer"
        echo "  stop           : Stop the timer"
        echo "  delete         : Delete the timer"
        echo "  pause          : Pause the timer"
        echo "  status         : Display the timer status"
        echo "Options:"
        echo "  HH:MM:SS       : Set timer duration in hours, minutes, and seconds"
        echo "  MM:SS          : Set timer duration in minutes and seconds"
        echo "  SS             : Set timer duration in seconds"
        exit 1
        ;;
    esac
    ;;
esac
