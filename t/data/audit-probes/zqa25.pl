package C; sub new { bless {v=>1}, shift } sub m { my ($s,@l)=@_; $_[1]=9; "@l" } package main; my @a=(1,2); print C->new->m(@a), "@a\n";
