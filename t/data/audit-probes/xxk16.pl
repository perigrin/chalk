my $s = "aXbXc"; my $n = 0; $s =~ s/X/$n++/ge; print "$s$n\n";
