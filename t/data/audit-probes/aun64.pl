package A; sub hi {"a"} package B; sub hi {"b"} package main; my $o = bless {}, "A"; for my $c ("B","A") { print $o->hi; bless $o, $c } print $o->hi, "\n";
