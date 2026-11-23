package C; our $i; sub get { $i //= bless {n=>0}, $_[0] } package main; my $o=C->get; $o->{n}++; print C->get->{n},"\n";
