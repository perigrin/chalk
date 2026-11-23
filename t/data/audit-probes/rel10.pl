my @o; for my $i (1..3) { my @t; push @t,$i; push @o,\@t } $o[0][0]=9; print join(",",map{"@$_"}@o),"\n";
