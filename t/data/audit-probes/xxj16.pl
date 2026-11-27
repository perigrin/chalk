my $s = "abc"; $s =~ s/(.)/$1$1/g; print "$s\n";
