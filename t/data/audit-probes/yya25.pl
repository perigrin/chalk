my $x=1; my $f = sub { my ($p)=@_; $_[0]=9; $p }; print $f->($x), "$x\n";
