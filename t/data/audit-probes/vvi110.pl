my $s = "aXbXc"; my @o; while ($s =~ /X/g) { push @o, pos($s); $s =~ s/^a/aa/ if @o == 1 } print "@o\n";
