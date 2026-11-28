package E; sub new { bless {m => $_[1]}, $_[0] } sub msg { $_[0]{m} } package main; eval { die E->new("boom") }; print $@->msg, "\n";
