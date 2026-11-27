my $r = \ (my $s = "abc"); $$r =~ s/b/B/; $$r =~ tr/c/C/; print "$s\n";
