my $buf = ""; open(my $fh, ">", \$buf) or die; print $fh "a", "b"; printf $fh "%03d", 7; close $fh; open($fh, ">>", \$buf) or die; print $fh "!"; close $fh; print "$buf\n";
