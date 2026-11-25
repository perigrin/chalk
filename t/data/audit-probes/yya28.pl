package C; sub new { bless {}, shift } sub m { my ($s,$p)=@_; $_[1]=9; $p } package main; my $x=1; print C->new->m($x), "$x\n";
