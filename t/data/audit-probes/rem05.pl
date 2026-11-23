package C; sub new { bless {v=>$_[1]}, $_[0] } sub v { $_[0]{v} } package main; my @o=map { C->new($_) } 1..3; $o[1]{v}=9; print join("",map{$_->v}@o),"\n";
