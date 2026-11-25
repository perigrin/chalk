my $n = 0; my $s = "a.b.c"; $s =~ s/\./$n++/ge; my $t = "1 2 3"; $t =~ s/(\d)/$1*2/ge; my $u = "aXb"; $u =~ s/X/"-" x 3/e; print "$s|$t|$u|$n\n";
