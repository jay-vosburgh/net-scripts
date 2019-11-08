#!/usr/bin/awk -f
#
# Process softnet_stat file, prints data in human readable format.
#
# Copyright 2010-2019 Jay Vosburgh <j.vosburgh@gmail.com>
# SPDX-License-Identifier: GPL-3.0
#
BEGIN {
	cpu = -1;
	if (ARGC == 1) {
		ARGC++;
		ARGV[1] = "/proc/net/softnet_stat";
	}
	tot_processed = 0;
	tot_dropped = 0;
	w_processed = 0;
	w_dropped = 0;
	w_time_sq = 0;
	w_rx_rps = 0;
	w_flow_lim = 0;
}

# Note: in recent kernels, cpu_collision is always 0
{
	cpu++;
	data[cpu, "processed"] = strtonum("0x" $1);
	l = length(data[cpu, "processed"]);
	if (l > w_processed)
		w_processed = l;

	data[cpu, "dropped"] = strtonum("0x" $2);
	l = length(data[cpu, "dropped"]);
	if (l > w_dropped)
		w_dropped = l;

	data[cpu, "time_sq"] = strtonum("0x" $3);
	l = length(data[cpu, "time_sq"]);
		if (l > w_time_sq)
			w_time_sq = l;

	cpu_coll = strtonum("0x" $9);
	if (cpu_coll)
	    printf("%03d: cpu_coll %u\n", cpu_coll);

	data[cpu, "rx_rps"] = strtonum("0x" $10);
	l = length(data[cpu, "rx_rps"]);
	if (l > w_rx_rps)
		w_rx_rps = l

	data[cpu, "flow_lim"] = strtonum("0x" $11);
	l = length(data[cpu, "flow_lim"]);
	if (l > w_flow_lim)
		w_flow_lim = l;

	tot_processed += data[cpu, "processed"];
	tot_dropped += data[cpu, "dropped"];
}

END {
    printf("total packets %u\n", tot_processed);
    for (i = 0; i <= cpu; i++) {
	if (data[i, "processed"] < data[i, "dropped"])
		printf("%03d: warning: processed %d < dropped %d\n",
			i, data[i, "processed"], data[i, "dropped"]);
	printf("%03d: proc %*u %5.2f%% drop %*u tm_sq %*u rx_rps %*u fl_lim %*u\n",
	       i, w_processed, data[i, "processed"],
	       (0.0 + data[i, "processed"] / tot_processed) * 100,
	       w_dropped, data[i, "dropped"],
	       w_time_sq, data[i, "time_sq"],
	       w_rx_rps, data[i, "rx_rps"],
	       w_flow_lim, data[i, "flow_lim"]);
    }
}

#        seq_printf(seq,
#                   "%08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x\n",
#                   sd->processed, sd->dropped, sd->time_squeeze, 0,
#                   0, 0, 0, 0, /* was fastroute */
#                   sd->cpu_collision, sd->received_rps, flow_limit_count);
