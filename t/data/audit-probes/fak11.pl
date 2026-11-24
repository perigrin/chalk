my %d=(inc=>sub { $_[0]+1 }, dbl=>sub { $_[0]*2 }); my $v=1; $v=$d{$_}->($v) for qw(inc dbl inc); print "$v\n";
