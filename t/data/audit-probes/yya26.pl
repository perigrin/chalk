my $x=1; my $f = sub { my ($p)=@_; $x=9; $p }; print $f->($x), "$x\n";
