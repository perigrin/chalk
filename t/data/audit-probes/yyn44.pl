open(my $fh, "<", \ "a\nb\nc\n") or die; my $n = 0; my $s = ""; while (<$fh>) { chomp; $n++; $s .= "$.$_" } close $fh; print "$n$s\n";
