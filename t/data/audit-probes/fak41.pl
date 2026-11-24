my $s="a"; my $ap=sub { $s.=$_[0] }; my $o=""; for my $c (qw(b c)) { $o.=$s; $ap->($c); $o.="|" } print "$o$s\n";
