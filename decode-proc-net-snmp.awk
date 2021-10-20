#!/usr/bin/awk -E
# assumes file in format like:
# H1: label1 label2 ...
# H1: value1 value2 ...
# which matches /proc/net/snmp and /proc/net/netstat
#
# with multiple files the script will combine inputs; when duplicate copies
# of the same input are provided, the difference is also printed.  E.g.,
#
# decode-proc-net-snmp.awk snmp.1 netstat.1 snmp.2 netstat.2
#
# will do what you'd expect.
#
# options:
# -z	only show line if value or difference is non-zero
# -c	do some heuristic checks (needs both snmp and netstat to make sense)
#
# default action if no filenames are provided is to process
# /proc/net/snmp and /proc/net/netstat
#
# Jay Vosburgh, j.vosburgh@gmail.com
# SPDX-License-Identifier: GPL-3.0

BEGIN {
	maxlabel = 0;
	maxhdr = 0;
	opt_sh_zero = 1;
	moreargs = 1;
	first = 1;
	do {
		if (ARGV[1] == "-z") {
			opt_sh_zero = 0;
			lshift_ARGV();
			continue;
		}
		if (ARGV[1] == "-c") {
			opt_check = 1;
			lshift_ARGV();
			continue;
		}
		moreargs = 0;
	} while (moreargs);

	if (ARGC == 1) {
		ARGV[1] = "/proc/net/snmp";
		ARGV[2] = "/proc/net/netstat";
		ARGC += 2;
	}
	printf("reading from");
	for (i = 1; i < ARGC; i++)
		printf(" %s", ARGV[i]);
	printf("\n");
}

function lshift_ARGV(_i)
{
	for (_i = 1; _i < ARGC; _i++)
		ARGV[_i] = ARGV[_i + 1];
	ARGC--;
}

{
	h1 = $1;
	if (length(h1) > maxhdr)
		maxhdr = length(h1);

	headers[h1]++;
	nf = split($0, h1tmp, " ");

#	printf "nf %d h1 %s headers %d\n", nf, h1, headers[h1];

	if (headers[h1] == 1 || headers[h1] == 3) {
		nfields[h1, headers[h1]] = nf;

		for (i = 2; i <= nf; i++) {
			labels[h1, headers[h1], i] = h1tmp[i];
			if (length(h1tmp[i]) > maxlabel) {
				maxlabel = length(h1tmp[i]);
			}
		}

		next;
	}

	if (headers[h1] == 2 || headers[h1] == 4) {
		if (nf != nfields[h1, headers[h1] - 1]) {
			printf "ERROR: nfields[%s, %d] %d != nf %d\n", h1,
				headers[h1] - 1,
				nfields[h1, headers[h1] - 1], nf;
		}

		for (i = 2; i <= nf; i++) {
			values[h1, headers[h1] - 1, i] = h1tmp[i];
		}

		next;
	}

	printf "ERROR: bad headers %d for h1 %s\n", headers[h1], h1;
}

function do_check()
{
# Misc, used below
#
# Tcp: InSegs		number of TCP segments received
# Tcp: InCsumErrors	number of TCP segments received with bad checksum
	tcp_insegs = diffs["Tcp:", "InSegs"];
	tcp_incsumerr = diffs["Tcp:", "InCsumErrors"];

# Retransmission rate
#
# Tcp: RetransSegs	number of TCP segments retransmitted
# Tcp: OutSegs		number of TCP segments sent
	tcp_rtsegs = diffs["Tcp:", "RetransSegs"];
	tcp_outsegs = diffs["Tcp:", "OutSegs"];
	if (tcp_outsegs) {
		rtorate = (tcp_rtsegs * 100.0) / tcp_outsegs;
		printf("%-*s Retransmission rate %f%%\n", maxhdr,
		       rtorate > 1.0 ? "WARN:" : "Note:", rtorate);
	}

# Misc checks
#
# Complain if checksum errors exceed 1% of incoming segments
	incsumrate = (tcp_incsumerr * 100.0) / tcp_insegs;
	if (incsumrate > 1.0)
		printf("%-*s TCP checksum errors %f%%\n", maxhdr,
		       "WARN:", incsumrate);

# Memory pressure
#
# TcpExt: PruneCalled		Times tried to reduce socket memory usage
# TcpExt: TCPRcvCollapsed	# of skbs collapsed (data combined)
# TcpExt: RcvPruned		Times instructed TCP to drop due to mem press
# TcpExt: OfoPruned		Times threw away data in ofo queue
	tcpext_prunec = diffs["TcpExt:", "PruneCalled"];
	tcpext_rcvcoll = diffs["TcpExt:", "TCPRcvCollapsed"];
	tcpext_rcvpr = diffs["TcpExt:", "RcvPruned"];
	tcpext_ofopr = diffs["TcpExt:", "OfoPruned"];
	if (tcpext_prunec)
		printf("%-*s %d Prune calls: collapsed %d recv %d ofo %d\n",
		       maxhdr, "WARN:", tcpext_prunec, tcpext_rcvoll,
		       tcpext_rcvpr, tcpext_ofopr);

# Misc drops 
#
# TcpExt: TCPBacklogDrop	Adding skb to TCP backlog queue
# TcpExt: PFMemallocDrop	PFMEMALLOC skb to !MEMALLOC socket
# TcpExt: TCPMinTTLDrop		IP TTL < min TTL (default min TTL == 0)
# TcpExt: TCPDeferAcceptDrop	bare ACK in TCP_DEFER_ACCEPT mode (harmless)
# TcpExt: IPReversePathFilter	Drop after fail rp_filter check
# TcpExt: ListenOverflows	TCP accept queue overflow
# TcpExt: ListenDrops		Catch-all for TCP incoming conn request drops
# TcpExt: TCPOFODrop		Drop if OFO and no rmem available for socket
# TcpExt: TCPZeroWindowDrop	Drop due to TCP recv window closed
# TcpExt: TCPRcvQDrop		No rmem when recv segment in ESTABLISHED state,
#				or C/R obscure case (TCP_REPAIR)
	tcpext_backlogd = diffs["TcpExt:", "TCPBacklogDrop"];
	tcpext_pfmemd = diffs["TcpExt:", "PFMemallocDrop"];
	tcpext_minttld = diffs["TcpExt:", "TCPMinTTLDrop"];
	tcpext_deferaccd = diffs["TcpExt:", "TCPDeferAcceptDrop"];
	tcpext_rpfilterd = diffs["TcpExt:", "IPReversePathFilter"];
	tcpext_listenovf = diffs["TcpExt:", "ListenOverflows"];
	tcpext_ldrop = diffs["TcpExt:", "ListenDrops"];
	tcpext_ofod = diffs["TcpExt:", "TCPOFODrop"];
	tcpext_zwind = diffs["TcpExt:", "TCPZeroWindowDrop"];
	tcpext_rcvqd = diffs["TcpExt:", "TCPRcvQDrop"];

	if (tcpext_backlogd)
		printf("%-*s %d drops: TCP socket backlog queue full\n",
		       maxhdr, "Note:", tcpext_backlogd);
	if (tcpext_pfmemd)
		printf("%-*s %d drops: PFMEMALLOC skb to non-MEMALLOC socket\n",
		       maxhdr, "Note:", tcpext_pfmemd);
	if (tcpext_minttld)
		printf("%-*s %d drops: IP TTL below minimum\n",
		       maxhdr, "Note:", tcpext_pfmemd);
	if (tcpext_deferaccd)
		printf("%-*s %d drops: TCP_DEFER_ACCEPT recv ACK-only segment\n",
		       maxhdr, "Note:", tcpext_deferaccd);
	if (tcpext_rpfilterd)
		printf("%-*s %d drops: failed reverse path filter test\n",
		       maxhdr, "Note:", tcpext_rpfilterd);
	if (tcpext_listenovf)
		printf("%-*s %d drops: TCP accept queue overflow\n",
		       maxhdr, "Note:", tcpext_listenovf);
	if (tcpext_ldrop)
		printf("%-*s %d drops: TCP incoming connect request catch-all\n",
		       maxhdr, "Note:", tcpext_ldrop);
	if (tcpext_ofod)
		printf("%-*s %d drops: TCP no rmem adding to OFO recv queue\n",
		       maxhdr, "Note:", tcpext_ldrop);
	if (tcpext_zwind)
		printf("%-*s %d drops: TCP receive window full\n",
		       maxhdr, "Note:", tcpext_ldrop);
	if (tcpext_rcvqd)
		printf("%-*s %d drops: TCP no rmem adding to recv queue\n",
		       maxhdr, "Note:", tcpext_ldrop);

# SYN flood
#
# TcpExt: TCPReqQFullDrop	req sock queue full (syn flood, syncookies off)
# TcpExt: TCPReqQFullDoCookies	req sock queue full (syn flood, syncookies on)
	tcpext_rqfulld = diffs["TcpExt:", "TCPReqQFullDrop"];
	tcpext_rqfullcook = diffs["TcpExt:", "TCPReqQFullDoCookies"];

	if (tcpext_rqfulld)
		printf("%-*s %d drops: TCP request queue full, syncookies off\n",
		       maxhdr, "Note:", tcpext_rqfulld);
	if (tcpext_rqfullcook)
		printf("%-*s %d cookie: TCP request queue full, syncookies on\n",
		       maxhdr, "Note:", tcpext_rqfullcook);

# Misc possible badness
#
# TcpExt: TCPSpuriousRtxHostQueues	skb retrans before original left host
	tcpext_spuriousrtx = diffs["TcpExt:", "TCPSpuriousRtxHostQueues"]
	if (tcpext_spuriousrtx)
		printf("%-*s %d retrans with original still queued on host\n",
		       maxhdr, "Note:", tcpext_spuriousrtx);
}

END {
	for (x in headers) {
		if (headers[x] == 3) {
			printf "ERROR: headers[%s] == 3, missing values\n", x;
		}

		if ((headers[x] == 4) && (nfields[x, 1] != nfields[x, 3])) {
			printf "ERROR: nfields[%s,1] %d != nfields[%s,3] %d\n",
				x, nfields[x, 1], x, nfields[x, 3];
		}

		for (y = 2; y <= nfields[x, 1]; y++) {
			if (headers[x] == 4) {
				diffs[x, labels[x, 1, y]] = values[x, 3, y] - \
					values[x, 1, y];
			} else {
				diffs[x, labels[x, 1, y]] = values[x, 1, y];
			}

			if (!opt_sh_zero && !diffs[x, labels[x, 1, y]])
				continue;

			printf("%-*s %-*s %14d", maxhdr, x, maxlabel,
			       labels[x, 1, y], values[x, 1, y]);
			if (headers[x] == 4) {
				printf(" %14d %14d",
				       values[x, 3, y],
				       values[x, 3, y] - values[x, 1, y]);
			}
			printf("\n");
		}
	}
	if (opt_check)
		do_check();
}
