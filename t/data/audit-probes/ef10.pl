my $o = bless {}, "A"; my $c1 = ref $o; my $p = bless $o, "B"; print "$c1 ", ref($o), "\n";
