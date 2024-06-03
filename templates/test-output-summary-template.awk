BEGIN {
    # Define column widths
    plan_width = 8
    req_rate_width = 8
    req_total_width = 9
    res_200_width = 7
    res_429_width = 7
    res_other_width = 9
    rl_pass_width = 8
    rl_fail_width = 8
    rl_success_percent_width = 10
    rate_200_width = 8
    rate_200_percent_width = 10
    key_rate_width = 8
    key_rate_percent_width = 10
    
    # Header
    printf "%-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s\n",
        plan_width, "Plan", req_eate_width, "Req Rate", req_total_width, "Req Total", res_200_width, "Res 200",
        res_429_width, "Res 429", res_other_width, "Res Other", rl_pass_width, "RRL Pass",
        rl_fail_width, "RRL Fail", rl_success_percent_width, "RRL Pass %", rate_200_width, "200 Rate",
        rate_200_percent_width, "200 Rate %", key_rate_width, "Key Rate", key_rate_percent_width, "Key Rate %"
}

{
    # Data rows
    printf "%-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s\n",
        plan_width, $1, req_rate_width, $2, req_total_width, $3, res_200_width, $4,
        res_429_width, $5, res_other_width, $6, rl_pass_width, $7,
        rl_fail_width, $8, rl_success_percent_width, $9, rate_200_width, $10,
        rate_200_percent_width, $11, key_rate_width, $12, key_rate_percent_width, $13
}
