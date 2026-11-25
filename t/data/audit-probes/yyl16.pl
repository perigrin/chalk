my $s = "abc"; (my $t = $s) =~ s/x*/-/g; (my $u = $s) =~ s/\b/|/g; (my $v = $s) =~ s/^/>/; (my $w = $s) =~ s/$/</; print "$t $u $v $w\n";
