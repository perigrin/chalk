my @l = (1,2); my $buf = ""; open(my $o, ">", \$buf); print $o scalar(@l); push @l, 3; print $o scalar(@l); close $o; print "$buf\n";
