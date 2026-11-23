package C; our $i; sub get { $i ||= {n=>0}; $i } package main; C::get()->{n}++; C::get()->{n}++; print C::get()->{n},"\n";
