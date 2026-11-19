my $s = "aXbXc"; my @p; while ($s =~ /X/g) { push @p, pos($s) } print "@p\n";
