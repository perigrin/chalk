package C; my $y=1; sub new { bless {}, shift } sub m { my ($s,$p)=@_; $y=9; $p } sub n { $y=9; my ($s,$p)=@_; $p } package main; print C->new->m($y), C->new->n($y), "\n";
