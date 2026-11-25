my $s=""; for (1..3) { late(); $s.=$main::n } print "$s\n"; sub late { $main::n++ }
