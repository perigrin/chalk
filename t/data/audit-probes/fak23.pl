sub each_item { my ($cb,@l)=@_; $cb->($_) for @l } my $s=0; each_item(sub { $s+=$_[0] }, 1,2,3); print "$s\n";
