package C; our $inst; sub get { $inst //= bless {n=>0}, shift } package main; C->get->{n}++; C->get->{n}++; print C->get->{n},"\n";
