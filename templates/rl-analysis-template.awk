function get_field(line, field_number) {
    split(line, fields, " ")
    return fields[field_number]
}

# Define a function to process timestamp string
function timestamp_to_epoch_ms(ts) {
    # remove the Z from end of timestamp
    ts = substr(ts, 1, length(ts)-1) 
    # Split the timestamp into parts
    split(ts, date_time_parts, "T")
    split(date_time_parts[1], date_parts, "-")

    # handle timestamps that lack ms element e.g. 2024-05-08T17:49:58Z
    millisecond_exist = date_time_parts[2] ~ /\./
    if (millisecond_exist) {
        split(date_time_parts[2], time_ms_parts, ".")
        split(time_ms_parts[1], time_parts, ":")
    } else {
        split(date_time_parts[2], time_parts, ":")
    }
    
    # Set year, month, day, hour, minute, and second
    year = date_parts[1]
    month = date_parts[2]
    day = date_parts[3]
    hour = time_parts[1]
    minute = time_parts[2]
    second = time_parts[3]
    millisecond = millisecond_exist ? time_ms_parts[2] : "000" 
    
    # add zero padding to ensure millisecond is 3 digits
    len = length(millisecond)
    if (len == 1) {
        millisecond = millisecond "00"
    } else if (len == 2) {
        millisecond = millisecond "0"
    }
    
    # Combine date parts for 'date' command
    date_string = sprintf("%s-%s-%s %s:%s:%s", year, month, day, hour, minute, second)

    cmd = "date -jf '%Y-%m-%d %H:%M:%S' '" date_string "' +%s"
    cmd | getline epoch
    close(cmd)
    
    # Combine epoch time in seconds and milliseconds
    return sprintf("%s%s", epoch, millisecond)
}

BEGIN {
    # Initialize variables
    line_count = 0
}

{
    # Store each line in the lines array
    lines[line_count++] = $0
}

END {
    rate_limit_window_ms = rate_limit_period * 1000
    status_200_count = 0
    status_429_count = 0
    status_other_count = 0
    rl_pass_count = 0
    rl_fail_count = 0
    rl200_pass_count = 0
    rl200_fail_count = 0
    rl429_pass_count = 0
    rl429_fail_count = 0

    # Iterate through the lines array
    for (i = 0; i < line_count; i++) {
        # Get the status code of the current line
        status_code = get_field(lines[i], 1)
        
        if (status_code == 200 || status_code == 429) {

            if (status_code == 200) {
                status_200_count++
            } else {
                status_429_count++
            }
            # Get the current timestamp
            current_timestamp = get_field(lines[i], 2)

            # Get the index of the line at the extent of the rate limit
            next_line_index = i + rate_limit

            if (next_line_index < line_count) {
                next_timestamp = get_field(lines[next_line_index], 2)

                current_epoch_ms = timestamp_to_epoch_ms(current_timestamp)
                next_epoch_ms = timestamp_to_epoch_ms(next_timestamp)

                # Get the millisecond difference
                difference_ms = current_epoch_ms - next_epoch_ms

                if (difference_ms > rate_limit_window_ms) {
                    # the requests are outside of the RRL window
                    if (status_code == 200) {
                        result = "RRL-pass"
                        reason = "200-out-RRL"
                        rl_pass_count++
                        rl200_pass_count++
                    } else {
                        result = "RRL-fail"
                        reason = "429-out-RRL"
                        rl_fail_count++
                        rl429_fail_count++
                    }
                } else {
                    # the requests are inside of the RRL window
                    if (status_code == 200) {
                        result = "RRL-fail"
                        reason = "200-in-RRL"
                        rl_fail_count++
                        rl200_fail_count++
                    } else {
                        result = "RRL-pass"
                        reason = "429-in-RRL"
                        rl_pass_count++
                        rl429_pass_count++
                    }
                }
            } else {
                # requests that occur within the initial rate limit request range should not be rate limited
                # i.e. if the rate limit is 5 per second, the first 5 requests should not be rate limited regardless of when they occur    
                if (status_code == 200) {
                    result = "RRL-pass"
                    reason = "200-in-init"
                    rl_pass_count++
                    rl200_pass_count++
                } else {
                    result = "RRL-fail"
                    reason = "429-in-init"
                    rl_fail_count++
                    rl429_fail_count++
                }
                next_timestamp = "n/a"
                difference_ms = "n/a"
            }
            print test_plan_file_name, i, next_line_index, current_timestamp, next_timestamp, status_code, difference_ms, rate_limit_window_ms, result, reason
        } else {
            status_other_count++
        }
    }   

    if (rate_limit_window_ms != 0) {
        normalised_key_rate_limit = (rate_limit / rate_limit_window_ms) * 1000 # normalise key rate limit to per second
        rl_success_percent = status_429_count == 0 ? 100 : (rl_pass_count / line_count) * 100
    } else {
        normalised_key_rate_limit = 0
        rl_pass_count = "n/a"
        rl_fail_count = "n/a"
        rl_success_percent = "n/a"
    }

    if (status_200_count != 0) {
        # calculate rate of 200 responses
        first_timestamp = get_field(lines[0], 2)
        last_timestamp = get_field(lines[line_count-1], 2)
        first_epoch = timestamp_to_epoch_ms(first_timestamp)
        last_epoch = timestamp_to_epoch_ms(last_timestamp)
        duration_ms = first_epoch - last_epoch # first is most recent
        rate_200 = int(status_200_count / (duration_ms / 1000)) # rounded
    } else {
        rate_200 = 0
    }

    if (normalised_key_rate_limit != 0) {
        key_rate_percent = int((rate_200 / normalised_key_rate_limit) * 100)
    } else {
        key_rate_percent = "n/a"
        normalised_key_rate_limit = "n/a"
    }

    if (req_rate != 0) {
        rate_200_percent = int((rate_200 / req_rate) * 100)
    } else {
        rate_200_percent = "n/a"
    }

    print test_plan_file_name, req_rate, line_count, status_200_count, status_429_count, status_other_count, rl_pass_count, rl_fail_count, rl_success_percent, rate_200, rate_200_percent, normalised_key_rate_limit, key_rate_percent >> summary_data_path
}
