sub apply { my ($f,@l)=@_; map { $f->($_) } @l } my $k=2; my @r=apply(sub { $_[0]*$k }, 1,2); $k=3; my @q=apply(sub { $_[0]*$k }, 1,2); print "@r @q\n";
