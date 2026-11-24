my $v=1; my @subs=(sub { $v+=1 }, sub { $v*=3 }); for my $s (@subs, reverse @subs) { $s->() } print "$v\n";
