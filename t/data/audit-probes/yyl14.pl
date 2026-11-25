my $s = "hello world"; $s =~ s/(\w+)/\u$1/g; my $t = "abc"; $t =~ s/b/[$&]/; my $u = "abc"; $u =~ s/(b)/$`|$'/; print "$s|$t|$u\n";
