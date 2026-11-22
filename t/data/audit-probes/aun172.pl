our $s = "ab"; sub ch { $s =~ s/a/z/ } my $t = $s; ch(); print "$t $s\n";
