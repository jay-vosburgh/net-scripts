#!/usr/bin/awk -f
#
# Print rt_cache stats in friendlier format
#
# Jay Vosburgh <j.vosburgh@gmail.com>
# SPDX-License-Identifier: GPL-3.0
#

BEGIN {
	cpu = -1;
	if (ARGC == 1) {
		ARGC++;
		ARGV[1] = "/proc/net/stat/rt_cache";
	}
	tot_processed = 0;
	tot_dropped = 0;
}

/^entries/ {
    next;
}

# since rt cache removal, in_hit, out_hit, gc_*, *hlist_search are all 0
#
#entries  in_hit in_slow_tot in_slow_mc in_no_route in_brd in_martian_dst
# in_martian_src  out_hit out_slow_tot out_slow_mc  gc_total gc_ignored
# gc_goal_miss gc_dst_overflow in_hlist_search out_hlist_search

{
	cpu++;
# entries is the same for all CPUs
	entries = strtonum("0x" $1);
	data[cpu, "in_slow_tot"] = strtonum("0x" $3);
	data[cpu, "in_slow_mc"] = strtonum("0x" $4);
	data[cpu, "in_no_route"] = strtonum("0x" $5);
	data[cpu, "in_brd"] = strtonum("0x" $6);
	data[cpu, "in_martian_dst"] = strtonum("0x" $7);
	data[cpu, "in_martian_src"] = strtonum("0x" $8);

	data[cpu, "out_slow_tot"] = strtonum("0x" $10);
	data[cpu, "out_slow_mc"] = strtonum("0x" $11);

	tot_in_slow += data[cpu, "in_slow_tot"];
}

END {
    printf("entries %u total tot_in_slow %u\n", entries, tot_in_slow);
    printf("   in_                                                      | out_\n");
    printf("   slow_tot   %%  slow_mc no_route      brd   mart_d   mart_s slow_tot  slow_mc\n");
    for (i = 0; i <= cpu; i++) {
	printf("%02d %8u %2u%% %8u %8u %8u %8u %8u %8u %8u\n",
	       i, data[i, "in_slow_tot"],
	       (0.0 + data[i, "in_slow_tot"] / tot_in_slow) * 100,
	       data[i, "in_slow_mc"],
	       data[i, "in_no_route"],
	       data[i, "in_brd"],
	       data[i, "in_martian_dst"],
	       data[i, "in_martian_src"],
	       data[i, "out_slow_tot"],
	       data[i, "out_slow_mc"]);
    }
}
