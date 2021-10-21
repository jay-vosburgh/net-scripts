#!/usr/bin/gawk -E
#
# Decode /proc/interrupts into something less unfriendly.
#
# With no arguments, summarizes /proc/interrupts from running system.
#
# -c : provide per-CPU summary
# -d : provide diff between two snapshots (-d -d for more detail)
# -i : provide per-IRQ summary
# -s : provide default summary even if other summaries requested
# -z : When showing a diff, include lines with no change
# -C : provide per-CPU detail for one specified CPU
#
# After options, any number of /proc/interrupt snapshot files may be
# specified.  If -d is supplied, exactly two snapshots must be provided.
#
# This ended up a bit more complicated than I'd expected.
#
# Jay Vosburgh <j.vosburgh@gmail.com>
# SPDX-License-Identifier: GPL-3.0

BEGIN {
	fnseq = 0;
	header = 0;
	first = 1;
	rpt_percpu = 0;
	rpt_perirq = 0;
	opt_diff = 0;
	opt_summary = 0;
	opt_showzero = 0;
	moreargs = 1;
	do {
		if (ARGV[first] == "-c") {
			rpt_percpu = -1;
			first++;
			continue;
		}
		if (ARGV[first] == "-d") {
			opt_diff++;
			first++;
			continue;
		}
		if (ARGV[first] == "-i") {
			rpt_perirq = 1;
			first++;
			continue;
		}
		if (ARGV[first] == "-s") {
			opt_summary = 1;
			first++;
			continue;
		}
		if (ARGV[first] == "-z") {
			opt_showzero = 1;
			first++;
			continue;
		}
		if (ARGV[first] == "-C") {
			rpt_percpu = 1;
			rpt_percpu_cpu = ARGV[first + 1] + 0;
			first += 2;
			continue;
		}
		moreargs = 0;
	} while (moreargs);

	if (ARGC - first == 0) {
		gather("/proc/interrupts");
	} else {
		for (i = first; i < ARGC; i++) {
			gather(ARGV[i]);
		}
	}

	if (fnseq > 1)
		check_irqnames();

	if (rpt_percpu < 0)
		report_sum_percpu();
	if (rpt_percpu > 0)
		report_specific_percpu();
	if (rpt_perirq)
		report_perirq();

	if (opt_summary || !(rpt_percpu || rpt_perirq))
		report_summary();
	exit(0);
}

function gather(fname)
{
	eathdr = 1;
	filenames[fnseq++] = fname;

	while (1) {
		rv = getline < fname;
		if (rv == -1) {
			printf("%s: %s\n", fname, ERRNO) > /dev/stderr;
			return;
		}
		if (rv == 0) {
			close(fname);
			return;
		}

		if (eathdr) {
			data[fname, "ncpu"] = NF;
			eathdr = 0;
			continue;
		}
		

		if (match($1, "[0-9]")) {
			iname = $1 + 0;
		} else {
			split($1, sp, ":");
			iname = sp[1] "";
		}
		irqnames[iname]++;
		data[fname, "irq"] = iname;

		data[fname, iname, "intr-total"] = 0;
		for (c = 0; c < data[fname, "ncpu"]; c++) {
			data[fname, iname, "intr-total"] += $(c + 2);
			data[fname, "__allirqs", "intr-total"] += $(c + 2);
			data[fname, iname, "intr-percpu", c] = $(c + 2);
			data[fname, "__allirqs", "intr-percpu", c] += $(c + 2);
		}

		data[fname, iname, "desc"] = $(data[fname, "ncpu"] + 2) " ";
		for (c = data[fname, "ncpu"] + 3; c <= NF; c++) {
			data[fname, iname, "desc"] = \
				data[fname, iname, "desc"] " " $c;
		}
		gsub("  ", " ", data[fname, iname, "desc"]);
	}
}

function report_one_summary(fname)
{
	_w1 = length(data[fname, "__allirqs", "intr-total"]);
	printf("ALL %*d %s\n", _w1, data[fname, "__allirqs", "intr-total"],
		fname);
	for (iname in irqnames) {
		if (!data[fname, iname, "intr-total"] && !opt_showzero)
			continue;
		printf("%3s %*d %s\n", iname,
		       _w1, data[fname, iname, "intr-total"],
		       data[fname, iname, "desc"]);
	}
}

function report_summary()
{
	if (opt_diff) {
		dname = filenames[0] " vs " filenames[1];
		make_diff(filenames[0], filenames[1], dname);
		_w1 = length(data[filenames[0], "__allirqs", "intr-total"]);
		_w2 = length(data[filenames[1], "__allirqs", "intr-total"]);
		_w3 = length(data[dname, "__allirqs", "intr-total"]);
		printf("IRQ Interrupt Totals: %s\n", dname);
		printf("ALL %*d  %*d  %*d\n",
		       _w1, data[filenames[0], "__allirqs", "intr-total"],
		       _w2, data[filenames[1], "__allirqs", "intr-total"],
		       _w3, data[dname, "__allirqs", "intr-total"]);
	}
	if (opt_diff > 1) {
		for (iname in irqnames) {
			printf("%3s %*d  %*d  %*d\n", iname,
			       _w1, data[filenames[0], iname, "intr-total"],
			       _w2, data[filenames[1], iname, "intr-total"],
			       _w3, data[dname, iname, "intr-total"]);
		}
	}
	if (opt_diff) {
		report_one_summary(dname);
	} else {
		for (fi = 0; fi < fnseq; fi++)
			report_one_summary(filenames[fi]);
	}
}

function xtics_or_irq(fname, iname)
{
	if (data[fname, iname, "xtics"] < 0)
		return data[fname, iname, "xtics"];
	else
		return iname;
}


function percent_me(num, dem)
{
	if (!dem)
		return 0.0;
	return ((0.0 + num) / dem) * 100;
}

function percpu_line(fname, _w1, c)
{
# print CPU number, number of interrupts, percentage / histogram of
# fraction of total number of interrupts
	printf("CPU %3d %*d %6.2f%%", c,
	       _w1, data[fname, "__allirqs", "intr-percpu", c],
	       percent_me(data[fname, "__allirqs", "intr-percpu", c],
			  data[fname, "__allirqs", "intr-total"]));
	histo_me(data[fname, "__allirqs", "intr-percpu", c],
		 data[fname, "__allirqs", "intr-total"]);
}	

function percpu_line_d(flname, c)
{
# print CPU number, irq difference from prior entry, and histogram of
# fraction of total difference from first to last CPUs
	printf("CPU %3d %16d %6.2f%%", c,
	       ptarget["__allirqs", "intr-percpu", c],
	       percent_me(ptarget["__allirqs", "intr-percpu", c],
			  data[flname, "__allirqs", "intr-percpu", c]));
	histo_me(ptarget["__allirqs", "intr-percpu", c],
		 data[flname, "__allirqs", "intr-percpu", c]);
}	

function report_one_percpu(fname)
{
	_w1 = length(data[fname, "__allirqs", "intr-total"]);
	printf("CPU ALL %*d %s\n", _w1, data[fname, "__allirqs", "intr-total"],
	       fname);
	for (c = 0; c < data[fname, "ncpu"]; c++) {
		percpu_line(fname, _w1, c);
	}
}

function report_diff_percpu(fname,	dnames, c, fi, flname)
{
	if (fnseq == 2) {
		report_one_percpu(fname);
		return;
	}

	flname = filenames[0] " vs " filenames[fnseq - 1];
	make_diff(filenames[0], filenames[fnseq - 1], flname);

	for (c = 0; c < data[fname, "ncpu"]; c++) {
		percpu_line(filenames[0], c);
		for (fi = 0; fi < fnseq - 1; fi++) {
			make_diff_percpu(filenames[fi], filenames[fi + 1], c);
			percpu_line_d(flname, c);
		}
	}
}

function report_sum_percpu()
{
	if (opt_diff) {
		dname = filenames[0] " vs " filenames[1];
		make_diff(filenames[0], filenames[1], dname);
		_w1 = length(data[filenames[0], "__allirqs", "intr-total"]);
		_w2 = length(data[filenames[1], "__allirqs", "intr-total"]);
		_w3 = length(data[dname, "__allirqs", "intr-total"]);
		printf("CPU Interrupt Totals: %s\n", dname);
		printf("CPU ALL %*d  %*d  %*d\n",
		       _w1, data[filenames[0], "__allirqs", "intr-total"],
		       _w2, data[filenames[1], "__allirqs", "intr-total"],
		       _w3, data[dname, "__allirqs", "intr-total"]);
		printf("\n");
	}
	if (opt_diff > 1) {
		for (c = 0; c < data[filenames[0], "ncpu"]; c++) {
			printf("CPU %3d %*d  %*d  %*d\n", c,
			       _w1, data[filenames[0], "__allirqs", "intr-percpu", c],
			       _w2, data[filenames[1], "__allirqs", "intr-percpu", c],
			       _w3, data[dname, "__allirqs", "intr-percpu", c]);
		}
		printf("\n");
	}
	if (opt_diff) {
		report_diff_percpu(dname);
	} else {
		for (fi = 0; fi < fnseq; fi++)
			report_one_percpu(filenames[fi]);
	}
}

function report_one_specific_percpu(fname)
{
	c = rpt_percpu_cpu;
	_w1 = length(data[fname, "__allirqs", "intr-percpu", c]);
	printf("ALL %*d CPU %3d %s\n",
	       _w1, data[fname, "__allirqs", "intr-percpu", c], c, fname);
	for (iname in irqnames) {
		printf("%3s %*d %6.2f%% %s\n", iname,
		       _w1, data[fname, iname, "intr-percpu", c],
		       percent_me(data[fname, iname, "intr-percpu", c],
				  data[fname, "__allirqs", "intr-percpu", c]),
		       data[fname, iname, "desc"]);
	}
}

function report_one_specific_percpu_diff(dname, fname1, fname2, c, 	iname)
{
	printf("CPU %3d diff %s\n", c, dname);
	_w1 = length(data[fname1, "__allirqs", "intr-percpu", c]);
	_w2 = length(data[fname2, "__allirqs", "intr-percpu", c]);
	_w3 = length(ptarget["__allirqs", "intr-percpu", c]);
	printf("ALL %*d  %*d  %*d\n",
	       _w1, data[fname1, "__allirqs", "intr-percpu", c],
	       _w2, data[fname2, "__allirqs", "intr-percpu", c],
	       _w3, ptarget["__allirqs", "intr-percpu", c]);
	for (iname in irqnames) {
		if (!ptarget[iname, "intr-percpu", c] && !opt_showzero)
			continue;
		printf("%3s %*d  %*d  %*d%s\n", iname,
		       _w1, data[fname1, iname, "intr-percpu", c],
		       _w2, data[fname2, iname, "intr-percpu", c],
		       _w3, ptarget[iname, "intr-percpu", c],
		       (opt_diff > 1) ? " " data[fname1, iname, "desc"] : "");
	}
}

function report_specific_percpu()
{
	if (opt_diff) {
		dname = filenames[0] " vs " filenames[1];
		make_diff_percpu(filenames[0], filenames[1], rpt_percpu_cpu);
	}
	if (opt_diff > 1) {
	}
	if (opt_diff) {
		report_one_specific_percpu_diff(dname, filenames[0],
						filenames[1], rpt_percpu_cpu);
	} else {
		for (fi = 0; fi < fnseq; fi++)
			report_one_specific_percpu(filenames[fi]);
	}
}

function report_one_perirq(fname)
{
	_w1 = length(data[fname, "__allirqs", "intr-total"]);
	printf("ALL %*d %s\n", 
	       _w1, data[fname, "__allirqs", "intr-total"], fname);

	for (iname in irqnames) {
		if (!data[fname, iname, "intr-total"] && !opt_showzero)
			continue;
		printf("%3s %*d %6.2f%%", iname,
		       _w1, data[fname, iname, "intr-total"],
		       percent_me(data[fname, iname, "intr-total"],
				  data[fname, "__allirqs", "intr-total"]));
		histo_me(data[fname, iname, "intr-total"],
			 data[fname, "__allirqs", "intr-total"]);
	}
}

function report_perirq()
{
	if (opt_diff) {
		dname = filenames[0] " vs " filenames[1];
		make_diff(filenames[0], filenames[1], dname);
		_w1 = length(data[filenames[0], "__allirqs", "intr-total"]);
		_w2 = length(data[filenames[1], "__allirqs", "intr-total"]);
		_w3 = length(data[dname, "__allirqs", "intr-total"]);
		printf("IRQ Interrupt Totals: %s\n", dname);
		printf("ALL %*d  %*d  %*d\n",
		       _w1, data[filenames[0], "__allirqs", "intr-total"],
		       _w2, data[filenames[1], "__allirqs", "intr-total"],
		       _w3, data[dname, "__allirqs", "intr-total"]);
		printf("\n");
	}
	if (opt_diff > 1) {
		for (iname in irqnames) {
			if (!data[dname, iname, "intr-total"] && !opt_showzero)
				continue;
			printf("%3s %*d  %*d  %*d\n", iname,
			       _w1, data[filenames[0], iname, "intr-total"],
			       _w2, data[filenames[1], iname, "intr-total"],
			       _w3, data[dname, iname, "intr-total"]);
		}
		printf("\n");
	}
	if (opt_diff) {
		report_one_perirq(dname);
	} else {
		for (fi = 0; fi < fnseq; fi++)
			report_one_perirq(filenames[fi]);
	}
}

function make_diff(fname1, fname2, fname3,	c, iname)
{
	data[fname3, "__allirqs", "intr-total"] = \
		data[fname2, "__allirqs", "intr-total"] - \
		data[fname1, "__allirqs", "intr-total"];

	if (data[fname1, "ncpu"] != data[fname2, "ncpu"]) {
		printf("ERROR: ncpu mismatch\n");
		printf("\"%s\" ncpu %d\n", fname1, data[fname1, "ncpu"]);
		printf("\"%s\" ncpu %d\n", fname2, data[fname2, "ncpu"]);
		exit(1);
	}
	data[fname3, "ncpu"] = data[fname1, "ncpu"];
	for (c = 0; c < data[fname1, "ncpu"]; c++) {
		data[fname3, "__allirqs", "intr-percpu", c] = \
			data[fname2, "__allirqs", "intr-percpu", c] - \
			data[fname1, "__allirqs", "intr-percpu", c];
	}

	for (iname in irqnames) {
		data[fname3, iname, "intr-total"] = \
			data[fname2, iname, "intr-total"] - \
			data[fname1, iname, "intr-total"];
		if (data[fname1, iname, "desc"] != data[fname2, iname, "desc"]) {
			printf("ERROR: desc mismatch\n");
			exit(1);
		}
		data[fname3, iname, "desc"] = data[fname1, iname, "desc"];
		for (c = 0; c < data[fname1, "ncpu"]; c++) {
			data[fname3, iname, "intr-percpu", c] = \
				data[fname2, iname, "intr-percpu", c] - \
				data[fname1, iname, "intr-percpu", c];
		}
	}
}

function make_diff_percpu(fname1, fname2, c,	 iname)
{
	ptarget["__allirqs", "intr-total"] = \
		data[fname2, "__allirqs", "intr-total"] - \
		data[fname1, "__allirqs", "intr-total"];

	if (data[fname1, "ncpu"] != data[fname2, "ncpu"]) {
		printf("ERROR: ncpu mismatch\n");
		printf("\"%s\" ncpu %d\n", fname1, data[fname1, "ncpu"]);
		printf("\"%s\" ncpu %d\n", fname2, data[fname2, "ncpu"]);
		exit(1);
	}
	ptarget["ncpu"] = data[fname1, "ncpu"];
	ptarget["__allirqs", "intr-percpu", c] =		      \
		data[fname2, "__allirqs", "intr-percpu", c] -	      \
		data[fname1, "__allirqs", "intr-percpu", c];

	for (iname in irqnames) {
		ptarget[iname, "intr-total"] = \
			data[fname2, iname, "intr-total"] - \
			data[fname1, iname, "intr-total"];
		if (data[fname1, iname, "desc"] != data[fname2, iname, "desc"]) {
			printf("ERROR: desc mismatch\n");
			exit(1);
		}
		ptarget[iname, "desc"] = data[fname1, iname, "desc"];
		ptarget[iname, "intr-percpu", c] =			\
			data[fname2, iname, "intr-percpu", c] -		\
			data[fname1, iname, "intr-percpu", c];
	}
}

function check_irqnames(	iname)
{
	for (iname in irqnames) {
		if (irqnames[iname] != fnseq)
			printf("ERROR: %s references %d expected %d\n",
			       iname, irqnames[iname], fnseq);
	}
}

function histo_me(num, dem,	_frac, _w, i)
{
	if (dem)
		_frac = (0.0 + num) / dem;
	else
		_frac = 0.0;
	_w = _frac * 50;

	printf(" ");
	for (i = 1; i < _w; i++)
		printf("=");
	printf("\n");
}
