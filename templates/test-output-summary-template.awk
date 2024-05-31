BEGIN {
    # Define column widths
    plan_width = 8
    req_total_width = 9
    res_200_width = 7
    res_429_width = 7
    res_other_width = 9
    rl_pass_width = 8
    rl_fail_width = 8
    rl_success_percent_width = 10
    rate_200_width = 8
    
    # Header
    printf "%-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s\n",
        plan_width, "Plan", req_total_width, "Req Total", res_200_width, "Res 200",
        res_429_width, "Res 429", res_other_width, "Res Other", rl_pass_width, "RRL Pass",
        rl_fail_width, "RRL Fail", rl_success_percent_width, "RRL Pass %", rate_200_width, "200 Rate"
}

{
    # Data rows
    printf "%-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %-*s\n",
        plan_width, $1, req_total_width, $2, res_200_width, $3,
        res_429_width, $4, res_other_width, $5, rl_pass_width, $6,
        rl_fail_width, $7, rl_success_percent_width, $8, rate_200_width, $9
}
