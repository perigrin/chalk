# ABOUTME: The LLVM runtime every T2 module links: its types, declarations, constants and
# ABOUTME: the t2_* functions, as .ll text (prelude) the printer puts at the module's head.
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Runtime;

# The runtime a slice-1 module calls: %Str is { i8*, i64 }; %Slot is a tag
# (0 undef, 1 Int -- an IV, 2 Num -- an NV, 3 Str, 4 a UV past IV_MAX; 5 and
# up references and the runtime's own) and an i64 payload (an IV's or a UV's
# bits, a Num's bits, a Str's heap pointer). Numbers print as perl prints them: %.15g, Inf, -Inf, NaN.
sub prelude { return '%Str = type { i8*, i64 }
%Slot = type { i8, i64 }
declare i32 @snprintf(i8*, i64, i8*, ...)
declare i8* @malloc(i64)
declare i8* @memcpy(i8*, i8*, i64)
declare i8* @getenv(i8*)
declare i64 @strlen(i8*)
declare double @strtod(i8*, i8**)
declare i64 @write(i32, i8*, i64)
@fmt_g = private unnamed_addr constant [6 x i8] c"%.15g\00"
@fmt_d = private unnamed_addr constant [4 x i8] c"%ld\00"
@lit_inf = private unnamed_addr constant [4 x i8] c"Inf\00"
@lit_ninf = private unnamed_addr constant [5 x i8] c"-Inf\00"
@lit_nan = private unnamed_addr constant [4 x i8] c"NaN\00"
@lit_one = private unnamed_addr constant [2 x i8] c"1\00"
@lit_zero = private unnamed_addr constant [2 x i8] c"0\00"
define internal %Str @t2_str(i8* %p, i64 %n) {
  %a = insertvalue %Str undef, i8* %p, 0
  %b = insertvalue %Str %a, i64 %n, 1
  ret %Str %b
}
define internal void @t2_print(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  call i64 @write(i32 1, i8* %p, i64 %n)
  ret void
}
define internal void @t2_eprint(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  call i64 @write(i32 2, i8* %p, i64 %n)
  ret void
}
; THE CALL STACK caller reads: three slots a frame (package, file, line),
; pushed by each call of a sub while the program reads caller.
@t2_frames = internal global %Array* null
define internal %Array* @t2_frames_get() {
  %f = load %Array*, %Array** @t2_frames
  %z = icmp eq %Array* %f, null
  br i1 %z, label %mk, label %ok
mk:
  %n = call %Array* @t2_new_array()
  store %Array* %n, %Array** @t2_frames
  ret %Array* %n
ok:
  ret %Array* %f
}
define internal void @t2_frame_push(%Str %p, %Str %f, i64 %l) {
  %a = call %Array* @t2_frames_get()
  %sp = call %Slot @t2_box_str(%Str %p)
  call void @t2_apush_d(%Array* %a, %Slot %sp)
  %sf = call %Slot @t2_box_str(%Str %f)
  call void @t2_apush_d(%Array* %a, %Slot %sf)
  %sl = call %Slot @t2_box_i64(i64 %l)
  call void @t2_apush_d(%Array* %a, %Slot %sl)
  ret void
}
define internal void @t2_frame_pop() {
  %a = call %Array* @t2_frames_get()
  %x = call %Slot @t2_apop_d(%Array* %a)
  %y = call %Slot @t2_apop_d(%Array* %a)
  %z = call %Slot @t2_apop_d(%Array* %a)
  ret void
}
; t2_frame_at(n) -> the index of frame n\'s package (n up from the innermost), or -1.
define internal i64 @t2_frame_at(i64 %n) {
  %a = call %Array* @t2_frames_get()
  %len = call i64 @t2_alen_d(%Array* %a)
  %n1 = add i64 %n, 1
  %k = mul i64 %n1, 3
  %neg = icmp slt i64 %n, 0
  %short = icmp slt i64 %len, %k
  %no = or i1 %neg, %short
  %base = sub i64 %len, %k
  %r = select i1 %no, i64 -1, i64 %base
  ret i64 %r
}
define internal %Array* @t2_caller(i64 %n) {
  %r = call %Array* @t2_new_array()
  %i = call i64 @t2_frame_at(i64 %n)
  %no = icmp slt i64 %i, 0
  br i1 %no, label %none, label %some
some:
  %a = call %Array* @t2_frames_get()
  %p = call %Slot @t2_aget_d(%Array* %a, i64 %i)
  call void @t2_apush_d(%Array* %r, %Slot %p)
  %i1 = add i64 %i, 1
  %f = call %Slot @t2_aget_d(%Array* %a, i64 %i1)
  call void @t2_apush_d(%Array* %r, %Slot %f)
  %i2 = add i64 %i, 2
  %l = call %Slot @t2_aget_d(%Array* %a, i64 %i2)
  call void @t2_apush_d(%Array* %r, %Slot %l)
  br label %none
none:
  ret %Array* %r
}
define internal %Slot @t2_caller_pkg(i64 %n) {
  %i = call i64 @t2_frame_at(i64 %n)
  %no = icmp slt i64 %i, 0
  br i1 %no, label %none, label %some
some:
  %a = call %Array* @t2_frames_get()
  %p = call %Slot @t2_aget_d(%Array* %a, i64 %i)
  ret %Slot %p
none:
  ret %Slot zeroinitializer
}
; substr(s, off[, len]): perl\'s translate_substr_offsets (pp.c), in signed ints --
; a negative offset counts from the end (still before it: clamped, unless the
; end is too). The bytes copied, NUL-ended. OUTSIDE THE STRING perl answers
; undef, with a warning where its warnings are on, which chalk raises none of:
; undef, or (stop: where they may be on, and for a substr that is written,
; which dies of it) stopped at run time (exit 255), not answered half right.
@lit_substr_out = private unnamed_addr constant [60 x i8] c"substr outside of string (perl warns): stopped (chalk, T2)\0A\00"
define internal %Slot @t2_substr(%Str %s, i64 %off, i64 %len, i1 %has, i1 %stop) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %oneg = icmp slt i64 %off, 0
  %npos = icmp sgt i64 %n, 0
  %adj = and i1 %oneg, %npos
  %offn = add i64 %off, %n
  %p1 = select i1 %adj, i64 %offn, i64 %off
  %past = icmp sgt i64 %p1, %n
  br i1 %past, label %undef, label %ends
ends:
  %lneg = icmp slt i64 %len, 0
  %fromend = add i64 %n, %len
  %p1neg = icmp slt i64 %p1, 0
  %p1len = add i64 %p1, %len
  %room = sub i64 %n, %p1
  %toolong = icmp sgt i64 %len, %room
  %fwd = select i1 %toolong, i64 %n, i64 %p1len
  %pos2 = select i1 %p1neg, i64 %p1len, i64 %fwd
  %withlen = select i1 %lneg, i64 %fromend, i64 %pos2
  %p2a = select i1 %has, i64 %withlen, i64 %n
  %p2neg = icmp slt i64 %p2a, 0
  %both = and i1 %p2neg, %p1neg
  br i1 %both, label %undef, label %clamp
clamp:
  %p2b = select i1 %p2neg, i64 0, i64 %p2a
  %p1b = select i1 %p1neg, i64 0, i64 %p1
  %under = icmp slt i64 %p2b, %p1b
  %p2c = select i1 %under, i64 %p1b, i64 %p2b
  %over = icmp sgt i64 %p2c, %n
  %p2 = select i1 %over, i64 %n, i64 %p2c
  %l = sub i64 %p2, %p1b
  %l1b = add i64 %l, 1
  %buf = call i8* @malloc(i64 %l1b)
  %src = getelementptr i8, i8* %p, i64 %p1b
  call i8* @memcpy(i8* %buf, i8* %src, i64 %l)
  %end = getelementptr i8, i8* %buf, i64 %l
  store i8 0, i8* %end
  %r = call %Str @t2_str(i8* %buf, i64 %l)
  %rs = call %Slot @t2_box_str(%Str %r)
  ret %Slot %rs
undef:
  br i1 %stop, label %stopped, label %none
none:
  ret %Slot zeroinitializer
stopped:
  call i64 @write(i32 2, i8* getelementptr ([60 x i8], [60 x i8]* @lit_substr_out, i64 0, i64 0), i64 59)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
; substr(s, off, len, r): s with the part substr(s, off, len) names replaced by r
; -- the offsets t2_substr takes (which stopped already were they outside).
define internal %Slot @t2_substr_rep(%Str %s, i64 %off, i64 %len, %Str %r) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %rp = extractvalue %Str %r, 0
  %rn = extractvalue %Str %r, 1
  %oneg = icmp slt i64 %off, 0
  %npos = icmp sgt i64 %n, 0
  %adj = and i1 %oneg, %npos
  %offn = add i64 %off, %n
  %p1 = select i1 %adj, i64 %offn, i64 %off
  %lneg = icmp slt i64 %len, 0
  %fromend = add i64 %n, %len
  %p1neg = icmp slt i64 %p1, 0
  %p1len = add i64 %p1, %len
  %room = sub i64 %n, %p1
  %toolong = icmp sgt i64 %len, %room
  %fwd = select i1 %toolong, i64 %n, i64 %p1len
  %pos2 = select i1 %p1neg, i64 %p1len, i64 %fwd
  %p2a = select i1 %lneg, i64 %fromend, i64 %pos2
  %p2neg = icmp slt i64 %p2a, 0
  %p2b = select i1 %p2neg, i64 0, i64 %p2a
  %p1b = select i1 %p1neg, i64 0, i64 %p1
  %under = icmp slt i64 %p2b, %p1b
  %p2c = select i1 %under, i64 %p1b, i64 %p2b
  %over = icmp sgt i64 %p2c, %n
  %p2 = select i1 %over, i64 %n, i64 %p2c
  %tail = sub i64 %n, %p2
  %l0 = add i64 %p1b, %rn
  %l = add i64 %l0, %tail
  %l1 = add i64 %l, 1
  %buf = call i8* @malloc(i64 %l1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %p1b)
  %mid = getelementptr i8, i8* %buf, i64 %p1b
  call i8* @memcpy(i8* %mid, i8* %rp, i64 %rn)
  %dst = getelementptr i8, i8* %buf, i64 %l0
  %src = getelementptr i8, i8* %p, i64 %p2
  call i8* @memcpy(i8* %dst, i8* %src, i64 %tail)
  %end = getelementptr i8, i8* %buf, i64 %l
  store i8 0, i8* %end
  %str = call %Str @t2_str(i8* %buf, i64 %l)
  %box = call %Slot @t2_box_str(%Str %str)
  ret %Slot %box
}
; index(s, t, pos): the first place at or after pos (clamped into the string) t is, or -1.
define internal i64 @t2_index(%Str %s, %Str %t, i64 %pos0) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %q = extractvalue %Str %t, 0
  %m = extractvalue %Str %t, 1
  %pneg = icmp slt i64 %pos0, 0
  %pa = select i1 %pneg, i64 0, i64 %pos0
  %pbig = icmp sgt i64 %pa, %n
  %pos = select i1 %pbig, i64 %n, i64 %pa
  br label %loop
loop:
  %i = phi i64 [ %pos, %entry ], [ %i1, %next ]
  %e = add i64 %i, %m
  %fits = icmp sle i64 %e, %n
  br i1 %fits, label %cmp, label %none
cmp:
  %at = getelementptr i8, i8* %p, i64 %i
  %c = call i32 @memcmp(i8* %at, i8* %q, i64 %m)
  %eq = icmp eq i32 %c, 0
  br i1 %eq, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
found:
  ret i64 %i
none:
  ret i64 -1
}
; END BLOCKS: the program\'s, in the order they run (t2_atexit adds one);
; t2_run_ends runs them once, at every way out -- the main line\'s end, an
; exit, a die (atexit(3) is not run by lli for an exit the program calls).
@t2_ends = internal global [64 x void ()*] zeroinitializer
@t2_nends = internal global i64 0
define internal void @t2_atexit(void ()* %f) {
  %n = load i64, i64* @t2_nends
  %p = getelementptr [64 x void ()*], [64 x void ()*]* @t2_ends, i64 0, i64 %n
  store void ()* %f, void ()** %p
  %n1 = add i64 %n, 1
  store i64 %n1, i64* @t2_nends
  ret void
}
define internal void @t2_run_ends() {
entry:
  %n = load i64, i64* @t2_nends
  store i64 0, i64* @t2_nends
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr [64 x void ()*], [64 x void ()*]* @t2_ends, i64 0, i64 %i
  %f = load void ()*, void ()** %p
  call void %f()
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}
define internal void @t2_exit(i64 %v) {
  %c = trunc i64 %v to i32
  call void @t2_run_ends()
  call void @exit(i32 %c)
  unreachable
}
define internal %Str @t2_concat(%Str %x, %Str %y) {
  %xp = extractvalue %Str %x, 0
  %xn = extractvalue %Str %x, 1
  %yp = extractvalue %Str %y, 0
  %yn = extractvalue %Str %y, 1
  %n = add i64 %xn, %yn
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %xp, i64 %xn)
  %mid = getelementptr i8, i8* %buf, i64 %xn
  call i8* @memcpy(i8* %mid, i8* %yp, i64 %yn)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_i64_str(i64 %v) {
  %buf = call i8* @malloc(i64 24)
  %f = getelementptr [4 x i8], [4 x i8]* @fmt_d, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 24, i8* %f, i64 %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_num_str(double %v) {
entry:
  %nan = fcmp uno double %v, %v
  br i1 %nan, label %isnan, label %notnan
isnan:
  %pn = getelementptr [4 x i8], [4 x i8]* @lit_nan, i64 0, i64 0
  %rn = call %Str @t2_str(i8* %pn, i64 3)
  ret %Str %rn
notnan:
  %pinf = fcmp oeq double %v, 0x7FF0000000000000
  br i1 %pinf, label %ispinf, label %notpinf
ispinf:
  %pi = getelementptr [4 x i8], [4 x i8]* @lit_inf, i64 0, i64 0
  %ri = call %Str @t2_str(i8* %pi, i64 3)
  ret %Str %ri
notpinf:
  %ninf = fcmp oeq double %v, 0xFFF0000000000000
  br i1 %ninf, label %isninf, label %finite
isninf:
  %pm = getelementptr [5 x i8], [5 x i8]* @lit_ninf, i64 0, i64 0
  %rm = call %Str @t2_str(i8* %pm, i64 4)
  ret %Str %rm
finite:
  %zero = fcmp oeq double %v, 0.0
  br i1 %zero, label %iszero, label %nonzero
iszero:
  %pz = getelementptr [2 x i8], [2 x i8]* @lit_zero, i64 0, i64 0
  %rz = call %Str @t2_str(i8* %pz, i64 1)
  ret %Str %rz
nonzero:
  %buf = call i8* @malloc(i64 32)
  %f = getelementptr [6 x i8], [6 x i8]* @fmt_g, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 32, i8* %f, double %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal double @t2_str_num(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %d = call double @strtod(i8* %buf, i8** null)
  ret double %d
}
define internal i64 @t2_str_i64(%Str %s) {
  %n = call %Slot @t2_str_numslot(%Str %s)
  %i = call i64 @t2_slot_i64(%Slot %n)
  ret i64 %i
}
declare i64 @strtoll(i8*, i8**, i32)
declare i64 @strtoull(i8*, i8**, i32)
; A STRING\'S NUMBER, perl\'s way: its leading integer kept whole (strtoll)
; unless a fraction or exponent follows, else its double.
define internal %Slot @t2_str_numslot(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %ep = alloca i8*
  %i = call i64 @strtoll(i8* %buf, i8** %ep, i32 10)
  %e = load i8*, i8** %ep
  %none = icmp eq i8* %e, %buf
  br i1 %none, label %num, label %after
after:
  %c = load i8, i8* %e
  %dot = icmp eq i8 %c, 46
  %ee = icmp eq i8 %c, 101
  %eE = icmp eq i8 %c, 69
  %f1 = or i1 %dot, %ee
  %frac = or i1 %f1, %eE
  %max = icmp eq i64 %i, 9223372036854775807
  %min = icmp eq i64 %i, -9223372036854775808
  %edge = or i1 %max, %min
  br i1 %frac, label %num, label %edged
edged:
  br i1 %edge, label %clamped, label %int
clamped:
  ; strtoll\'s IV_MAX or IV_MIN is the string\'s or where it clamped one past:
  ; strtoull reads the same digits, and agrees only on the string\'s own
  ; ("9223372036854775807" is an Int, as perl\'s; through a double it was
  ; 9.22337203685478e+18). Past IV_MAX and within UV_MAX perl\'s is a UV
  ; (grok_number\'s IS_NUMBER_IN_UV); below IV_MIN, or past UV_MAX, a Num.
  %ue = alloca i8*
  call void @t2_set_errno(i32 0)
  %u = call i64 @strtoull(i8* %buf, i8** %ue, i32 10)
  %own = icmp eq i64 %u, %i
  br i1 %own, label %int, label %past
past:
  br i1 %min, label %num, label %uvq
uvq:
  ; (strtoull says ERANGE past UV_MAX; within it, its value is the string\'s)
  %er = call i32 @t2_errno()
  %range = icmp eq i32 %er, 34
  br i1 %range, label %num, label %uv
uv:
  %su = call %Slot @t2_box_uv(i64 %u)
  ret %Slot %su
int:
  %si = call %Slot @t2_box_i64(i64 %i)
  ret %Slot %si
num:
  %d = call double @strtod(i8* %buf, i8** null)
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_numify(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %undef [ i8 1, label %same
                               i8 2, label %same
                               i8 4, label %same
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
same:
  ret %Slot %s
str:
  %v = extractvalue %Slot %s, 1
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %r = call %Slot @t2_str_numslot(%Str %sv)
  ret %Slot %r
undef:
  %z = call %Slot @t2_box_i64(i64 0)
  ret %Slot %z
ref:
  ; A REFERENCE AS A NUMBER is its address (perl\'s refaddr): == compares them.
  %ra = extractvalue %Slot %s, 1
  %rs = call %Slot @t2_box_i64(i64 %ra)
  ret %Slot %rs
}
define internal %Str @t2_bool_str(i1 %b) {
  %p = getelementptr [2 x i8], [2 x i8]* @lit_one, i64 0, i64 0
  %n = zext i1 %b to i64
  %r = call %Str @t2_str(i8* %p, i64 %n)
  ret %Str %r
}
define internal double @t2_bool_num(i1 %b) {
  %d = uitofp i1 %b to double
  ret double %d
}
define internal %Slot @t2_slot(i8 %t, i64 %v) {
  %a = insertvalue %Slot undef, i8 %t, 0
  %b = insertvalue %Slot %a, i64 %v, 1
  ret %Slot %b
}
define internal %Slot @t2_box_i64(i64 %v) {
  %s = call %Slot @t2_slot(i8 1, i64 %v)
  ret %Slot %s
}
; PERL\'S THREE NUMERIC FORMS (sv.h): an IV (tag 1), a UV (tag 4) -- an integer
; past IV_MAX, up to UV_MAX, its payload the unsigned bits -- and an NV (tag
; 2). A UV is only ever past IV_MAX: an unsigned result within IV_MAX is boxed
; an IV, so one value has one form here.
define internal %Slot @t2_box_uv(i64 %u) {
  %big = icmp slt i64 %u, 0
  %t = select i1 %big, i8 4, i8 1
  %s = call %Slot @t2_slot(i8 %t, i64 %u)
  ret %Slot %s
}
declare i32* @__errno_location()
define internal i32 @t2_errno() {
  %p = call i32* @__errno_location()
  %e = load i32, i32* %p
  ret i32 %e
}
define internal void @t2_set_errno(i32 %e) {
  %p = call i32* @__errno_location()
  store i32 %e, i32* %p
  ret void
}
@fmt_u = private unnamed_addr constant [4 x i8] c"%lu\00"
define internal %Str @t2_u64_str(i64 %v) {
  %buf = call i8* @malloc(i64 24)
  %f = getelementptr [4 x i8], [4 x i8]* @fmt_u, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 24, i8* %f, i64 %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
; t2_nv_please(d) -> an NV as perl\'s integer ops read it (SvIV_please,
; lossless_NV_to_IV): a whole number below 2**53 in size is an IV; any other
; stays an NV (past 2**53 its low bits are already lost).
declare double @llvm.fabs.f64(double)
define internal %Slot @t2_nv_please(double %d) {
entry:
  %a = call double @llvm.fabs.f64(double %d)
  %small = fcmp olt double %a, 9007199254740992.0
  %t = call double @llvm.trunc.f64(double %d)
  %whole = fcmp oeq double %t, %d
  %int = and i1 %small, %whole
  br i1 %int, label %iv, label %nv
iv:
  %i = fptosi double %d to i64
  %si = call %Slot @t2_box_i64(i64 %i)
  ret %Slot %si
nv:
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
; t2_str_dotted(s) -> s\'s number has a decimal point and no exponent
; ("1.0", "12.5"): grok_number\'s IS_NUMBER_IN_UV with IS_NUMBER_NOT_INT, an
; NV perl\'s integer ops never read as an integer -- where "1e15" is one.
define internal i1 @t2_str_dotted(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  br label %ws
ws:
  %i0 = phi i64 [ 0, %entry ], [ %i0n, %wsn ]
  %e0 = icmp sge i64 %i0, %n
  br i1 %e0, label %no, label %wsc
wsc:
  %c0p = getelementptr i8, i8* %p, i64 %i0
  %c0 = load i8, i8* %c0p
  %sp = icmp eq i8 %c0, 32
  %t1 = icmp uge i8 %c0, 9
  %t2 = icmp ule i8 %c0, 13
  %ctl = and i1 %t1, %t2
  %white = or i1 %sp, %ctl
  %plus = icmp eq i8 %c0, 43
  %minus = icmp eq i8 %c0, 45
  %sign = or i1 %plus, %minus
  %skip = or i1 %white, %sign
  br i1 %skip, label %wsn, label %dig
wsn:
  %i0n = add i64 %i0, 1
  br label %ws
dig:
  %i1 = phi i64 [ %i0, %wsc ], [ %i1n, %dign ]
  %e1 = icmp sge i64 %i1, %n
  br i1 %e1, label %no, label %digc
digc:
  %c1p = getelementptr i8, i8* %p, i64 %i1
  %c1 = load i8, i8* %c1p
  %d1a = icmp uge i8 %c1, 48
  %d1b = icmp ule i8 %c1, 57
  %d1 = and i1 %d1a, %d1b
  br i1 %d1, label %dign, label %dot
dign:
  %i1n = add i64 %i1, 1
  br label %dig
dot:
  %isdot = icmp eq i8 %c1, 46
  br i1 %isdot, label %frac, label %no
frac:
  %i2 = phi i64 [ %i1, %dot ], [ %i2n, %fracn ]
  %i2n = add i64 %i2, 1
  %e2 = icmp sge i64 %i2n, %n
  br i1 %e2, label %yes, label %fracc
fracc:
  %c2p = getelementptr i8, i8* %p, i64 %i2n
  %c2 = load i8, i8* %c2p
  %d2a = icmp uge i8 %c2, 48
  %d2b = icmp ule i8 %c2, 57
  %d2 = and i1 %d2a, %d2b
  br i1 %d2, label %fracn, label %exp
fracn:
  br label %frac
exp:
  %le = icmp eq i8 %c2, 101
  %ue = icmp eq i8 %c2, 69
  %ise = or i1 %le, %ue
  %r = xor i1 %ise, true
  ret i1 %r
yes:
  ret i1 1
no:
  ret i1 0
}
; t2_arith_num(x) -> x as perl\'s numeric ops read it (SvIV_please_nomg): an
; integer -- an IV (tag 1) or a UV (tag 4) -- where it is one, else an NV (tag
; 2). An NV a whole number below 2**53 is an integer; a string\'s own integer
; is (an IV or a UV, read whole), and so is its number where that is a whole
; one below 2**53 ("1e15") but has no decimal point ("1.0" stays an NV);
; undef is 0, a reference its address.
define internal %Slot @t2_arith_num(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %other [ i8 1, label %same
                               i8 4, label %same
                               i8 2, label %num
                               i8 3, label %str ]
same:
  ret %Slot %s
num:
  %v = extractvalue %Slot %s, 1
  %d = bitcast i64 %v to double
  %rn = call %Slot @t2_nv_please(double %d)
  ret %Slot %rn
str:
  %n = call %Slot @t2_slot_numify(%Slot %s)
  %nt = extractvalue %Slot %n, 0
  %isnv = icmp eq i8 %nt, 2
  br i1 %isnv, label %strnv, label %strint
strint:
  ret %Slot %n
strnv:
  %pv = extractvalue %Slot %s, 1
  %pp = inttoptr i64 %pv to %Str*
  %sv = load %Str, %Str* %pp
  %dotted = call i1 @t2_str_dotted(%Str %sv)
  br i1 %dotted, label %strint, label %please
please:
  %nb = extractvalue %Slot %n, 1
  %nd = bitcast i64 %nb to double
  %rs = call %Slot @t2_nv_please(double %nd)
  ret %Slot %rs
other:
  %o = call %Slot @t2_slot_numify(%Slot %s)
  ret %Slot %o
}
; t2_wide(x) -> an integer x (tag 1 or 4) exactly, in 128 bits.
define internal i128 @t2_wide(%Slot %x) {
  %t = extractvalue %Slot %x, 0
  %v = extractvalue %Slot %x, 1
  %isu = icmp eq i8 %t, 4
  %z = zext i64 %v to i128
  %s = sext i64 %v to i128
  %r = select i1 %isu, i128 %z, i128 %s
  ret i128 %r
}
; t2_int_or_nv(r, negexact) -> the exact integer r as perl keeps it: an IV
; or a UV within [IV_MIN, UV_MAX]; below IV_MIN with its size within UV_MAX,
; where negexact (pp_add\'s, pp_subtract\'s), -(NV)|r|; else undef (tag 0):
; perl\'s NV of its operands\' NVs is the caller\'s to make.
define internal %Slot @t2_int_or_nv(i128 %r, i1 %negexact) {
entry:
  %lo = icmp sge i128 %r, -9223372036854775808
  %hi = icmp sle i128 %r, 18446744073709551615
  %in = and i1 %lo, %hi
  br i1 %in, label %int, label %out
int:
  %b = trunc i128 %r to i64
  %big = icmp sgt i128 %r, 9223372036854775807
  %t = select i1 %big, i8 4, i8 1
  %s = call %Slot @t2_slot(i8 %t, i64 %b)
  ret %Slot %s
out:
  %neg = icmp slt i128 %r, 0
  %mag = sub i128 0, %r
  %fits = icmp sle i128 %mag, 18446744073709551615
  %nf = and i1 %neg, %fits
  %use = and i1 %nf, %negexact
  br i1 %use, label %nv, label %none
nv:
  %m = trunc i128 %mag to i64
  %md = uitofp i64 %m to double
  %d = fneg double %md
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
none:
  ret %Slot zeroinitializer
}
; t2_cast_iv(d) / t2_cast_uv(d): an NV\'s integer as perl\'s SvIV and SvUV
; read it (cast_iv, cast_uv): truncated; past IV_MAX the UV\'s bits (so SvIV
; of 1e20 is -1), below IV_MIN IV_MIN, past UV_MAX UV_MAX, NaN 0.
define internal i64 @t2_cast_iv(double %d) {
entry:
  %ltiv = fcmp olt double %d, 9223372036854775808.0
  br i1 %ltiv, label %iv, label %uvq
iv:
  %ltmin = fcmp olt double %d, -9223372036854775808.0
  br i1 %ltmin, label %min, label %cast
min:
  ret i64 -9223372036854775808
cast:
  %i = fptosi double %d to i64
  ret i64 %i
uvq:
  %ltuv = fcmp olt double %d, 18446744073709551616.0
  br i1 %ltuv, label %uv, label %top
uv:
  %u = fptoui double %d to i64
  ret i64 %u
top:
  %pos = fcmp ogt double %d, 0.0
  %r = select i1 %pos, i64 -1, i64 0
  ret i64 %r
}
; (cast_uv\'s bits are cast_iv\'s: below 0 it is (UV)(IV)d, past UV_MAX UV_MAX)
define internal i64 @t2_cast_uv(double %d) {
  %u = call i64 @t2_cast_iv(double %d)
  ret i64 %u
}
; t2_cstr(s): s as a NUL-terminated C string (a copy).
; t2_ftdir(path): perl\'s -d -- 1 a directory, \'\' something else, undef nothing.
; t2_chdir(path): perl\'s chdir -- 1, or \'\'.
declare i8* @opendir(i8*)
declare i32 @closedir(i8*)
declare i32 @access(i8*, i32)
declare i32 @chdir(i8*)
define internal i8* @t2_cstr(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %c = call i8* @malloc(i64 %n1)
  call i8* @memmove(i8* %c, i8* %p, i64 %n)
  %e = getelementptr i8, i8* %c, i64 %n
  store i8 0, i8* %e
  ret i8* %c
}
define internal %Slot @t2_ftdir(%Str %s) {
entry:
  %c = call i8* @t2_cstr(%Str %s)
  %d = call i8* @opendir(i8* %c)
  %isdir = icmp ne i8* %d, null
  br i1 %isdir, label %dir, label %other
dir:
  call i32 @closedir(i8* %d)
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
other:
  %a = call i32 @access(i8* %c, i32 0)
  %there = icmp eq i32 %a, 0
  br i1 %there, label %file, label %none
file:
  %no = call %Str @t2_str(i8* getelementptr ([1 x i8], [1 x i8]* @t2_empty, i64 0, i64 0), i64 0)
  %nos = call %Slot @t2_box_str(%Str %no)
  ret %Slot %nos
none:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
}
define internal %Slot @t2_chdir(%Str %s) {
entry:
  %c = call i8* @t2_cstr(%Str %s)
  %r = call i32 @chdir(i8* %c)
  %ok = icmp eq i32 %r, 0
  br i1 %ok, label %yes, label %no
yes:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
no:
  %e = call %Str @t2_str(i8* getelementptr ([1 x i8], [1 x i8]* @t2_empty, i64 0, i64 0), i64 0)
  %es = call %Slot @t2_box_str(%Str %e)
  ret %Slot %es
}
@t2_empty = private unnamed_addr constant [1 x i8] c"\00"
; t2_slot_int(x) / t2_slot_rand(x): perl\'s int and rand of a slot.
declare double @llvm.trunc.f64(double)
declare i32 @rand()
; (pp_int: an integer -- an NV or a string perl reads as one too -- is
; itself; an NV truncated is an IV or a UV while one holds it, else its
; floor or ceiling; Inf and NaN themselves)
declare double @llvm.floor.f64(double)
declare double @llvm.ceil.f64(double)
define internal %Slot @t2_slot_int(%Slot %s) {
entry:
  %x = call %Slot @t2_arith_num(%Slot %s)
  %tx = extractvalue %Slot %x, 0
  %isnv = icmp eq i8 %tx, 2
  br i1 %isnv, label %nv, label %same
same:
  ret %Slot %x
nv:
  %d = call double @t2_slot_num(%Slot %x)
  %a = call double @llvm.fabs.f64(double %d)
  %fin = fcmp olt double %a, 0x7FF0000000000000
  br i1 %fin, label %finite, label %keep
keep:
  ret %Slot %x
finite:
  %pos = fcmp oge double %d, 0.0
  br i1 %pos, label %p, label %n
p:
  %puv = fcmp olt double %d, 18446744073709551616.0
  br i1 %puv, label %pu, label %pf
pu:
  %u = fptoui double %d to i64
  %su = call %Slot @t2_box_uv(i64 %u)
  ret %Slot %su
pf:
  %fl = call double @llvm.floor.f64(double %d)
  %sf = call %Slot @t2_box_num(double %fl)
  ret %Slot %sf
n:
  %niv = fcmp ogt double %d, -9223372036854775808.0
  br i1 %niv, label %ni, label %nf
ni:
  %i = fptosi double %d to i64
  %si = call %Slot @t2_box_i64(i64 %i)
  ret %Slot %si
nf:
  %ce = call double @llvm.ceil.f64(double %d)
  %sc = call %Slot @t2_box_num(double %ce)
  ret %Slot %sc
}
; t2_slot_abs(x): perl\'s abs (pp_abs) -- of an integer (an NV or a string
; perl reads as one too) its size, an IV or a UV (abs(IV_MIN) is a UV); of
; any other NV its fabs; undef 0.
define internal %Slot @t2_slot_abs(%Slot %s) {
entry:
  %x = call %Slot @t2_arith_num(%Slot %s)
  %tx = extractvalue %Slot %x, 0
  %isnv = icmp eq i8 %tx, 2
  br i1 %isnv, label %nv, label %int
int:
  %w = call i128 @t2_wide(%Slot %x)
  %neg = icmp slt i128 %w, 0
  %m = sub i128 0, %w
  %a = select i1 %neg, i128 %m, i128 %w
  %r = call %Slot @t2_int_or_nv(i128 %a, i1 0)
  ret %Slot %r
nv:
  %d = call double @t2_slot_num(%Slot %x)
  %f = call double @llvm.fabs.f64(double %d)
  %sf = call %Slot @t2_box_num(double %f)
  ret %Slot %sf
}
define internal %Slot @t2_slot_rand(%Slot %s) {
  %x = call double @t2_slot_num(%Slot %s)
  %z = fcmp oeq double %x, 0.0
  %m = select i1 %z, double 1.0, double %x
  %r = call i32 @rand()
  %rd = sitofp i32 %r to double
  %u = fdiv double %rd, 2147483648.0
  %v = fmul double %u, %m
  %b = call %Slot @t2_box_num(double %v)
  ret %Slot %b
}
define internal %Slot @t2_box_num(double %v) {
  %i = bitcast double %v to i64
  %s = call %Slot @t2_slot(i8 2, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_box_str(%Str %v) {
  %m = call i8* @malloc(i64 16)
  %p = bitcast i8* %m to %Str*
  store %Str %v, %Str* %p
  %i = ptrtoint %Str* %p to i64
  %s = call %Slot @t2_slot(i8 3, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_env(i8* %k) {
entry:
  %v = call i8* @getenv(i8* %k)
  %none = icmp eq i8* %v, null
  br i1 %none, label %undef, label %set
undef:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
set:
  %n = call i64 @strlen(i8* %v)
  %s = call %Str @t2_str(i8* %v, i64 %n)
  %b = call %Slot @t2_box_str(%Str %s)
  ret %Slot %b
}
define internal %Slot @t2_box_bool(i1 %b) {
entry:
  br i1 %b, label %t, label %f
t:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
f:
  %e = call %Str @t2_str(i8* null, i64 0)
  %no = call %Slot @t2_box_str(%Str %e)
  ret %Slot %no
}
declare void @exit(i32)
define internal double @t2_div(double %x, double %y, i8* %msg, i64 %n) {
entry:
  %z = fcmp oeq double %y, 0.0
  br i1 %z, label %die, label %ok
die:
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret double 0.0
ok:
  %q = fdiv double %x, %y
  ret double %q
}
define internal i64 @t2_mod(i64 %x, i64 %y, i8* %msg, i64 %n) {
entry:
  %z = icmp eq i64 %y, 0
  br i1 %z, label %die, label %ok
die:
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret i64 0
ok:
  ; (IV_MIN % -1 is 0, as perl\'s: srem would overflow)
  %m1 = icmp eq i64 %y, -1
  %y1 = select i1 %m1, i64 1, i64 %y
  %r = srem i64 %x, %y1
  %rnz = icmp ne i64 %r, 0
  %rneg = icmp slt i64 %r, 0
  %yneg = icmp slt i64 %y, 0
  %diff = xor i1 %rneg, %yneg
  %fix = and i1 %rnz, %diff
  %r2 = add i64 %r, %y
  %res = select i1 %fix, i64 %r2, i64 %r
  ret i64 %res
}
; t2_slot_mod(x, y, msg, n): perl\'s % (pp_modulo) on what the operands hold:
; integers (an IV, a UV, an NV that is one below 2**64 truncated) by their
; sizes in UVs, the result\'s sign the right side\'s -- a UV where it is past
; IV_MAX; a right side past UV_MAX in size, or a left one where the right
; is not, by fmod. Zero dies, naming where.
declare double @fmod(double, double)
define internal %Slot @t2_slot_mod(%Slot %x0, %Slot %y0, i8* %msg, i64 %n) {
entry:
  %y = call %Slot @t2_arith_num(%Slot %y0)
  %ty = extractvalue %Slot %y, 0
  %yv = extractvalue %Slot %y, 1
  %ynv = icmp eq i8 %ty, 2
  br i1 %ynv, label %rnv, label %rint
rint:
  %yuv = icmp eq i8 %ty, 4
  %yneg0 = icmp slt i64 %yv, 0
  %ynotuv = xor i1 %yuv, true
  %rneg = and i1 %yneg0, %ynotuv
  %ymag = sub i64 0, %yv
  %right = select i1 %rneg, i64 %ymag, i64 %yv
  br label %left
rnv:
  %yd0 = bitcast i64 %yv to double
  %rnegd = fcmp olt double %yd0, 0.0
  %ydn = fneg double %yd0
  %yd = select i1 %rnegd, double %ydn, double %yd0
  %yin = fcmp olt double %yd, 18446744073709551616.0
  %ydu = fptoui double %yd to i64
  %rightd = select i1 %yin, i64 %ydu, i64 0
  br i1 %yin, label %left, label %dbl_r
left:
  %R = phi i64 [ %right, %rint ], [ %rightd, %rnv ]
  %RN = phi i1 [ %rneg, %rint ], [ %rnegd, %rnv ]
  %Rvalid = phi i1 [ false, %rint ], [ true, %rnv ]
  %Rd = phi double [ 0.0, %rint ], [ %yd, %rnv ]
  %x = call %Slot @t2_arith_num(%Slot %x0)
  %tx = extractvalue %Slot %x, 0
  %xv = extractvalue %Slot %x, 1
  %xnv = icmp eq i8 %tx, 2
  br i1 %xnv, label %lnv, label %lint
lint:
  %xuv = icmp eq i8 %tx, 4
  %xneg0 = icmp slt i64 %xv, 0
  %xnotuv = xor i1 %xuv, true
  %lneg = and i1 %xneg0, %xnotuv
  %xmag = sub i64 0, %xv
  %L = select i1 %lneg, i64 %xmag, i64 %xv
  br label %ints
lnv:
  %xd0 = bitcast i64 %xv to double
  %lnegd = fcmp olt double %xd0, 0.0
  %xdn = fneg double %xd0
  %xd = select i1 %lnegd, double %xdn, double %xd0
  %xin = fcmp olt double %xd, 18446744073709551616.0
  br i1 %xin, label %lnvint, label %dbl_l
lnvint:
  %Ld = fptoui double %xd to i64
  br label %ints
ints:
  %LL = phi i64 [ %L, %lint ], [ %Ld, %lnvint ]
  %LN = phi i1 [ %lneg, %lint ], [ %lnegd, %lnvint ]
  %z = icmp eq i64 %R, 0
  br i1 %z, label %die, label %idiv
idiv:
  %a0 = urem i64 %LL, %R
  %diff = xor i1 %LN, %RN
  %anz = icmp ne i64 %a0, 0
  %fix = and i1 %diff, %anz
  %a1 = sub i64 %R, %a0
  %ans = select i1 %fix, i64 %a1, i64 %a0
  br i1 %RN, label %ineg, label %ipos
ipos:
  %sp = call %Slot @t2_box_uv(i64 %ans)
  ret %Slot %sp
ineg:
  %wa = zext i64 %ans to i128
  %wn = sub i128 0, %wa
  %sn = call %Slot @t2_int_or_nv(i128 %wn, i1 1)
  ret %Slot %sn
dbl_l:
  ; (the left past UV_MAX, the right within it: both floored to whole numbers)
  %xf = fadd double %xd, 0.5
  %dl = call double @llvm.floor.f64(double %xf)
  %rf0 = fadd double %Rd, 0.5
  %rf = call double @llvm.floor.f64(double %rf0)
  %ru = uitofp i64 %R to double
  %dr = select i1 %Rvalid, double %rf, double %ru
  br label %dbl
dbl_r:
  ; (the right past UV_MAX: the left\'s NV as it is)
  %xa = call double @t2_slot_num(%Slot %x0)
  %xan = fcmp olt double %xa, 0.0
  %xaa = call double @llvm.fabs.f64(double %xa)
  br label %dbl
dbl:
  %DL = phi double [ %dl, %dbl_l ], [ %xaa, %dbl_r ]
  %DR = phi double [ %dr, %dbl_l ], [ %yd, %dbl_r ]
  %DLN = phi i1 [ %lnegd, %dbl_l ], [ %xan, %dbl_r ]
  %DRN = phi i1 [ %RN, %dbl_l ], [ %rnegd, %dbl_r ]
  %dz = fcmp oeq double %DR, 0.0
  br i1 %dz, label %die, label %ddiv
ddiv:
  %f0 = call double @fmod(double %DL, double %DR)
  %ddiff = xor i1 %DLN, %DRN
  %fnz = fcmp une double %f0, 0.0
  %dfix = and i1 %ddiff, %fnz
  %f1 = fsub double %DR, %f0
  %f2 = select i1 %dfix, double %f1, double %f0
  %f3 = fneg double %f2
  %f = select i1 %DRN, double %f3, double %f2
  %sf = call %Slot @t2_box_num(double %f)
  ret %Slot %sf
die:
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret %Slot zeroinitializer
}
; t2_slot_div(x, y, msg, n): perl\'s / (pp_divide): two integers\' exact
; quotient where the left is past 2**53 in size (where an NV would lose it)
; -- an IV or a UV, or an NV where it is below IV_MIN -- else the NVs\'
; quotient. Zero dies, naming where.
define internal %Slot @t2_slot_div(%Slot %x0, %Slot %y0, i8* %msg, i64 %n) {
entry:
  %y = call %Slot @t2_arith_num(%Slot %y0)
  %x = call %Slot @t2_arith_num(%Slot %x0)
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %nx = icmp eq i8 %tx, 2
  %ny = icmp eq i8 %ty, 2
  %either = or i1 %nx, %ny
  br i1 %either, label %nums, label %ints
ints:
  %wx = call i128 @t2_wide(%Slot %x)
  %wy = call i128 @t2_wide(%Slot %y)
  %xneg = icmp slt i128 %wx, 0
  %yneg = icmp slt i128 %wy, 0
  %mx0 = sub i128 0, %wx
  %my0 = sub i128 0, %wy
  %mx = select i1 %xneg, i128 %mx0, i128 %wx
  %my = select i1 %yneg, i128 %my0, i128 %wy
  %L = trunc i128 %mx to i64
  %R = trunc i128 %my to i64
  %z = icmp eq i64 %R, 0
  br i1 %z, label %die, label %try
try:
  %ge = icmp uge i64 %L, %R
  %big = icmp ugt i64 %L, 9007199254740992
  %go = and i1 %ge, %big
  br i1 %go, label %idiv, label %nums
idiv:
  %rem = urem i64 %L, %R
  %exact = icmp eq i64 %rem, 0
  br i1 %exact, label %iq, label %nums
iq:
  %q = udiv i64 %L, %R
  %wq = zext i64 %q to i128
  %sgn = xor i1 %xneg, %yneg
  %nq = sub i128 0, %wq
  %rq = select i1 %sgn, i128 %nq, i128 %wq
  %sq = call %Slot @t2_int_or_nv(i128 %rq, i1 1)
  ret %Slot %sq
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = call double @t2_div(double %dx, double %dy, i8* %msg, i64 %n)
  %sd = call %Slot @t2_box_num(double %d)
  ret %Slot %sd
die:
  %m = call %Str @t2_str(i8* %msg, i64 %n)
  call void @t2_die_unwind(%Str %m)
  ret %Slot zeroinitializer
}
; PERL\'S ++ AND --. A string of letters then digits, starting with a letter,
; increments by magic ("az" -> "ba", "Zz" -> "AAa", "a9" -> "b0"); any other
; string, and -- always, go by its number -- an Int when it is a whole one.
define internal i1 @t2_is_magic(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %no, label %first
first:
  %c0 = load i8, i8* %p
  %l0 = call i1 @t2_is_letter(i8 %c0)
  ; (perl\'s /^[a-zA-Z]*[0-9]*$/: no letters at all is magic too -- "007"++ is "008")
  %g0 = icmp uge i8 %c0, 48
  %e0 = icmp ule i8 %c0, 57
  %d0 = and i1 %g0, %e0
  %ok0 = or i1 %l0, %d0
  br i1 %ok0, label %loop, label %no
loop:
  %i = phi i64 [ 1, %first ], [ %i1, %next ]
  %digits = phi i1 [ %d0, %first ], [ %d1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %yes
body:
  %cp = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %cp
  %isl = call i1 @t2_is_letter(i8 %c)
  %ge0 = icmp uge i8 %c, 48
  %le9 = icmp ule i8 %c, 57
  %isd = and i1 %ge0, %le9
  ; a letter after a digit ends the pattern
  %lad = and i1 %isl, %digits
  %neither = xor i1 %isl, true
  %notd = xor i1 %isd, true
  %bad0 = and i1 %neither, %notd
  %bad = or i1 %bad0, %lad
  br i1 %bad, label %no, label %next
next:
  %i1 = add i64 %i, 1
  %d1 = or i1 %digits, %isd
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
define internal i1 @t2_is_letter(i8 %c) {
  %lo1 = icmp uge i8 %c, 97
  %lo2 = icmp ule i8 %c, 122
  %lo = and i1 %lo1, %lo2
  %up1 = icmp uge i8 %c, 65
  %up2 = icmp ule i8 %c, 90
  %up = and i1 %up1, %up2
  %r = or i1 %lo, %up
  ret i1 %r
}
define internal %Str @t2_str_magic_inc(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 2
  %buf = call i8* @malloc(i64 %n1)
  %dst = getelementptr i8, i8* %buf, i64 1
  call i8* @memcpy(i8* %dst, i8* %p, i64 %n)
  %last = sub i64 %n, 1
  br label %loop
loop:
  %i = phi i64 [ %last, %entry ], [ %im1, %carry ]
  %cp = getelementptr i8, i8* %dst, i64 %i
  %c = load i8, i8* %cp
  %isz = icmp eq i8 %c, 122
  %isZ = icmp eq i8 %c, 90
  %is9 = icmp eq i8 %c, 57
  %wrap = or i1 %isz, %isZ
  %wrap2 = or i1 %wrap, %is9
  br i1 %wrap2, label %carry, label %bump
bump:
  %c1 = add i8 %c, 1
  store i8 %c1, i8* %cp
  %r = call %Str @t2_str(i8* %dst, i64 %n)
  ret %Str %r
carry:
  %low = select i1 %isz, i8 97, i8 48
  %w = select i1 %isZ, i8 65, i8 %low
  store i8 %w, i8* %cp
  %im1 = sub i64 %i, 1
  %done = icmp slt i64 %im1, 0
  br i1 %done, label %grow, label %loop
grow:
  ; carried off the front: a new first character of the first\'s kind
  %f = load i8, i8* %dst
  %fA = icmp eq i8 %f, 65
  %f0 = icmp eq i8 %f, 48
  %lead0 = select i1 %fA, i8 65, i8 97
  %lead = select i1 %f0, i8 49, i8 %lead0   ; (a digit\'s is 1: "99"++ is "100")
  store i8 %lead, i8* %buf
  %n2 = add i64 %n, 1
  %g = call %Str @t2_str(i8* %buf, i64 %n2)
  ret %Str %g
}
; (perl\'s ++ and -- (sv.c\'s inc and dec): a value perl reads as an integer
; steps as one -- IV_MAX ++ is a UV, UV_MAX ++ the NV 2**64, IV_MIN -- an
; NV; anything else its NV)
define internal %Slot @t2_slot_step(%Slot %s, i64 %by, i1 %magic) {
entry:
  %t = extractvalue %Slot %s, 0
  %isstr = icmp eq i8 %t, 3
  br i1 %isstr, label %str, label %numeric
numeric:
  %x = call %Slot @t2_arith_num(%Slot %s)
  %tx = extractvalue %Slot %x, 0
  %isnv = icmp eq i8 %tx, 2
  br i1 %isnv, label %num, label %int
int:
  %w = call i128 @t2_wide(%Slot %x)
  %wby = sext i64 %by to i128
  %r = add i128 %w, %wby
  %si = call %Slot @t2_int_or_nv(i128 %r, i1 1)
  %st = extractvalue %Slot %si, 0
  %fell = icmp eq i8 %st, 0
  br i1 %fell, label %num, label %intok
intok:
  ret %Slot %si
num:
  %d = call double @t2_slot_num(%Slot %x)
  %dby = sitofp i64 %by to double
  %dr = fadd double %d, %dby
  %sn = call %Slot @t2_box_num(double %dr)
  ret %Slot %sn
str:
  %pv = extractvalue %Slot %s, 1
  %pp = inttoptr i64 %pv to %Str*
  %sv = load %Str, %Str* %pp
  %ism = call i1 @t2_is_magic(%Str %sv)
  %domagic = and i1 %ism, %magic
  br i1 %domagic, label %magicinc, label %numeric
magicinc:
  %ms = call %Str @t2_str_magic_inc(%Str %sv)
  %mslot = call %Slot @t2_box_str(%Str %ms)
  ret %Slot %mslot
}
define internal %Slot @t2_slot_inc(%Slot %s) {
  %r = call %Slot @t2_slot_step(%Slot %s, i64 1, i1 1)
  ret %Slot %r
}
define internal %Slot @t2_slot_dec(%Slot %s) {
  %r = call %Slot @t2_slot_step(%Slot %s, i64 -1, i1 0)
  ret %Slot %r
}
define internal i1 @t2_defined(%Slot %s) {
  %t = extractvalue %Slot %s, 0
  %d = icmp ne i8 %t, 0
  ret i1 %d
}
define internal double @t2_slot_num(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 4, label %uv
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
int:
  %di = sitofp i64 %v to double
  ret double %di
uv:
  %du = uitofp i64 %v to double
  ret double %du
num:
  %dn = bitcast i64 %v to double
  ret double %dn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %ds = call double @t2_str_num(%Str %sv)
  ret double %ds
undef:
  ret double 0.0
ref:
  %da = sitofp i64 %v to double
  ret double %da
}
; t2_slot_i64(s) -> perl\'s SvIV of s: an IV\'s own; a UV\'s bits (SvIV of
; 9223372036854775808 is IV_MIN, as perl\'s); an NV\'s cast_iv; a string\'s
; integer read whole.
define internal i64 @t2_slot_i64(%Slot %s0) {
entry:
  %s = call %Slot @t2_slot_numify(%Slot %s0)
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  %isnv = icmp eq i8 %t, 2
  br i1 %isnv, label %nv, label %int
int:
  ret i64 %v
nv:
  %d = bitcast i64 %v to double
  %i = call i64 @t2_cast_iv(double %d)
  ret i64 %i
}
declare { i64, i1 } @llvm.umul.with.overflow.i64(i64, i64)
; PERL\'S ARITHMETIC ON TWO SCALARS (pp_add, pp_subtract, pp_multiply): each
; operand read as an integer where perl reads one (t2_arith_num); two
; integers give the exact result while it fits an IV or a UV -- a sum or a
; difference below IV_MIN, within UV_MAX in size, is that size\'s NV, negated
; -- else, as for anything else, the operands\' NVs\' result.
define internal %Slot @t2_slot_add(%Slot %x0, %Slot %y0) {
entry:
  %x = call %Slot @t2_arith_num(%Slot %x0)
  %y = call %Slot @t2_arith_num(%Slot %y0)
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %nx = icmp eq i8 %tx, 2
  %ny = icmp eq i8 %ty, 2
  %either = or i1 %nx, %ny
  br i1 %either, label %nums, label %ints
ints:
  %wx = call i128 @t2_wide(%Slot %x)
  %wy = call i128 @t2_wide(%Slot %y)
  %r = add i128 %wx, %wy
  %s = call %Slot @t2_int_or_nv(i128 %r, i1 1)
  %st = extractvalue %Slot %s, 0
  %fell = icmp eq i8 %st, 0
  br i1 %fell, label %nums, label %int
int:
  ret %Slot %s
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fadd double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
define internal %Slot @t2_slot_sub(%Slot %x0, %Slot %y0) {
entry:
  %x = call %Slot @t2_arith_num(%Slot %x0)
  %y = call %Slot @t2_arith_num(%Slot %y0)
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %nx = icmp eq i8 %tx, 2
  %ny = icmp eq i8 %ty, 2
  %either = or i1 %nx, %ny
  br i1 %either, label %nums, label %ints
ints:
  %wx = call i128 @t2_wide(%Slot %x)
  %wy = call i128 @t2_wide(%Slot %y)
  %r = sub i128 %wx, %wy
  %s = call %Slot @t2_int_or_nv(i128 %r, i1 1)
  %st = extractvalue %Slot %s, 0
  %fell = icmp eq i8 %st, 0
  br i1 %fell, label %nums, label %int
int:
  ret %Slot %s
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fsub double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}
; -x, perl\'s (pp_negate): an integer\'s negation (-IV_MIN is a UV, - of a UV
; past 2**63 an NV), an NV\'s (-0.0 prints 0); a string that begins with a
; letter or _ gets a "-", one with a "+" (or a lone "-") its sign turned;
; "-" then a digit or "." is a number, read as an integer where perl reads
; one. "-" then anything else hangs on whether perl reads it as a number
; ("-inf" does, "-abc" does not): stopped, not guessed.
@lit_neg_stop = private unnamed_addr constant [50 x i8] c"unary minus of a \22-\22 string: stopped (chalk, T2)\0A\00"
define internal %Slot @t2_slot_neg(%Slot %x) {
entry:
  %t = extractvalue %Slot %x, 0
  %isstr = icmp eq i8 %t, 3
  br i1 %isstr, label %str, label %notstr
notstr:
  ; (an NV perl has not read as an integer is negated as one)
  %isnv = icmp eq i8 %t, 2
  br i1 %isnv, label %nv, label %num
nv:
  %nb = extractvalue %Slot %x, 1
  %nd = bitcast i64 %nb to double
  %nn = fneg double %nd
  %ns = call %Slot @t2_box_num(double %nn)
  ret %Slot %ns
num:
  %a = call %Slot @t2_arith_num(%Slot %x)
  %at = extractvalue %Slot %a, 0
  %anv = icmp eq i8 %at, 2
  br i1 %anv, label %anum, label %aint
anum:
  %ad = call double @t2_slot_num(%Slot %a)
  %an = fneg double %ad
  %as = call %Slot @t2_box_num(double %an)
  ret %Slot %as
aint:
  %w = call i128 @t2_wide(%Slot %a)
  %r0 = sub i128 0, %w
  %r = call %Slot @t2_int_or_nv(i128 %r0, i1 1)
  ret %Slot %r
str:
  %s = call %Str @t2_slot_str(%Slot %x)
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %num, label %first
first:
  %c = load i8, i8* %p
  %let = call i1 @t2_is_letter(i8 %c)
  %und = icmp eq i8 %c, 95
  %id = or i1 %let, %und
  br i1 %id, label %prefix, label %sign
prefix:
  %m = call %Str @t2_str(i8* getelementptr ([2 x i8], [2 x i8]* @lit_minus, i64 0, i64 0), i64 1)
  %j = call %Str @t2_concat(%Str %m, %Str %s)
  %jb = call %Slot @t2_box_str(%Str %j)
  ret %Slot %jb
sign:
  %plus = icmp eq i8 %c, 43
  br i1 %plus, label %flip, label %minus
minus:
  %ism = icmp eq i8 %c, 45
  br i1 %ism, label %after, label %num
after:
  %lone = icmp eq i64 %n, 1
  br i1 %lone, label %flip, label %next
next:
  %p1 = getelementptr i8, i8* %p, i64 1
  %c1 = load i8, i8* %p1
  %d0 = icmp uge i8 %c1, 48
  %d1 = icmp ule i8 %c1, 57
  %dig = and i1 %d0, %d1
  %dot = icmp eq i8 %c1, 46
  %numy = or i1 %dig, %dot
  br i1 %numy, label %num, label %stop
stop:
  call void @t2_stop(i8* getelementptr ([50 x i8], [50 x i8]* @lit_neg_stop, i64 0, i64 0), i64 49)
  unreachable
flip:
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n1)
  %to = select i1 %plus, i8 45, i8 43
  store i8 %to, i8* %buf
  %f = call %Str @t2_str(i8* %buf, i64 %n)
  %fb = call %Slot @t2_box_str(%Str %f)
  ret %Slot %fb
}
@lit_minus = private unnamed_addr constant [2 x i8] c"-\00"
; ref \$x: "REF" when $x holds a reference (tags 5..9), else "SCALAR". (T2
; holds no glob, lvalue or vstring values, the other answers perl gives.)
@lit_kind_ref = private unnamed_addr constant [4 x i8] c"REF\00"
@lit_kind_scalar = private unnamed_addr constant [7 x i8] c"SCALAR\00"
define internal %Slot @t2_kind_of_ref(%Slot %x) {
  %t = extractvalue %Slot %x, 0
  %lo = icmp uge i8 %t, 5
  %hi = icmp ule i8 %t, 9
  %isref = and i1 %lo, %hi
  %rs = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_kind_ref, i64 0, i64 0), i64 3)
  %ss = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_kind_scalar, i64 0, i64 0), i64 6)
  %s = select i1 %isref, %Str %rs, %Str %ss
  %b = call %Slot @t2_box_str(%Str %s)
  ret %Slot %b
}
; (a product past what an IV or a UV holds is its operands\' NVs\' product, either sign)
define internal %Slot @t2_slot_mul(%Slot %x0, %Slot %y0) {
entry:
  %x = call %Slot @t2_arith_num(%Slot %x0)
  %y = call %Slot @t2_arith_num(%Slot %y0)
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %nx = icmp eq i8 %tx, 2
  %ny = icmp eq i8 %ty, 2
  %either = or i1 %nx, %ny
  br i1 %either, label %nums, label %ints
ints:
  %wx = call i128 @t2_wide(%Slot %x)
  %wy = call i128 @t2_wide(%Slot %y)
  %r = mul i128 %wx, %wy
  %s = call %Slot @t2_int_or_nv(i128 %r, i1 0)
  %st = extractvalue %Slot %s, 0
  %fell = icmp eq i8 %st, 0
  br i1 %fell, label %nums, label %int
int:
  ret %Slot %s
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %d = fmul double %dx, %dy
  %sn = call %Slot @t2_box_num(double %d)
  ret %Slot %sn
}

define internal %Str @t2_slot_str(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 4, label %uv
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
int:
  %si = call %Str @t2_i64_str(i64 %v)
  ret %Str %si
uv:
  %su = call %Str @t2_u64_str(i64 %v)
  ret %Str %su
num:
  %dn = bitcast i64 %v to double
  %sn = call %Str @t2_num_str(double %dn)
  ret %Str %sn
str:
  %p = inttoptr i64 %v to %Str*
  %ss = load %Str, %Str* %p
  ret %Str %ss
undef:
  %e = call %Str @t2_str(i8* null, i64 0)
  ret %Str %e
ref:
  %rs = call %Str @t2_ref_str(%Slot %s)
  ret %Str %rs
}
@fmt_ref = private unnamed_addr constant [12 x i8] c"%.*s(0x%lx)\00"
@lit_eqhash = private unnamed_addr constant [6 x i8] c"=HASH\00"
; t2_ref_str(r) -> perl\'s string of a reference: HASH(0x...), ARRAY(0x...),
; or Class=HASH(0x...) for an object.
define internal %Str @t2_ref_str(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %addr = extractvalue %Slot %s, 1
  %kind = call %Str @t2_reftype(%Slot %s)
  %c = call %Slot @t2_class_of(%Slot %s)
  br label %h
h:
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %fmt
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  %rxn = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_regexp, i64 0, i64 0), i64 6)
  %rxc = call i64 @t2_strcmp(%Str %cn, %Str %rxn)
  %isrx = icmp eq i64 %rxc, 0
  br i1 %isrx, label %qr, label %obj2
qr:
  %pk = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_qrpat, i64 0, i64 0), i64 7)
  %pv = call %Slot @t2_hget(%Slot %s, %Str %pk)
  %ps = call %Str @t2_slot_str(%Slot %pv)
  ret %Str %ps
obj2:
  %eq = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_eqhash, i64 0, i64 0), i64 1)
  %bt = call %Str @t2_basetype(%Slot %s)
  %eh = call %Str @t2_concat(%Str %eq, %Str %bt)
  %ck = call %Str @t2_concat(%Str %kind, %Str %eh)
  br label %fmt
fmt:
  %pre = phi %Str [ %kind, %h ], [ %ck, %obj2 ]
  %pp = extractvalue %Str %pre, 0
  %pl = extractvalue %Str %pre, 1
  %pl32 = trunc i64 %pl to i32
  %cap = add i64 %pl, 32
  %buf = call i8* @malloc(i64 %cap)
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 %cap, i8* getelementptr ([12 x i8], [12 x i8]* @fmt_ref, i64 0, i64 0), i32 %pl32, i8* %pp, i64 %addr)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}

; %Array: { len, cap, elements } -- a `my @a`, its elements %Slot.
; (field 4: the class a bless gave it, undef until -- an array\'s or a hash\'s)
%Array = type { i64, i64, %Slot*, %Meta*, %Slot }
declare i8* @realloc(i8*, i64)
declare i8* @memmove(i8*, i8*, i64)
define internal %Array* @t2_new_array() {
  %m = call i8* @malloc(i64 48)
  %a = bitcast i8* %m to %Array*
  store %Array zeroinitializer, %Array* %a
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_default, %Meta** %mp
  ret %Array* %a
}
define internal i64 @t2_alen_d(%Array* %a) {
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %n = load i64, i64* %lp
  ret i64 %n
}
; t2_agrow(a, n): room for n elements, the new ones undef.
define internal void @t2_agrow(%Array* %a, i64 %n) {
entry:
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 1
  %cap = load i64, i64* %cp
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %fits = icmp sle i64 %n, %cap
  br i1 %fits, label %fill, label %grow
grow:
  %c2 = mul i64 %cap, 2
  %big = icmp sgt i64 %c2, %n
  %c3 = select i1 %big, i64 %c2, i64 %n
  %c4 = add i64 %c3, 4
  %bytes = mul i64 %c4, 16
  %old = load %Slot*, %Slot** %ep
  %o8 = bitcast %Slot* %old to i8*
  %new8 = call i8* @realloc(i8* %o8, i64 %bytes)
  %new = bitcast i8* %new8 to %Slot*
  store %Slot* %new, %Slot** %ep
  store i64 %c4, i64* %cp
  br label %fill
fill:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %len = load i64, i64* %lp
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ %len, %fill ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr %Slot, %Slot* %els, i64 %i
  store %Slot { i8 0, i64 1 }, %Slot* %p   ; (absent: perl\'s hole)
  %i1 = add i64 %i, 1
  br label %loop
done:
  %longer = icmp sgt i64 %n, %len
  %nl = select i1 %longer, i64 %n, i64 %len
  store i64 %nl, i64* %lp
  ret void
}
define internal void @t2_apush_d(%Array* %a, %Slot %v) {
  %n = call i64 @t2_alen(%Array* %a)
  %n1 = add i64 %n, 1
  call void @t2_agrow(%Array* %a, i64 %n1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %n
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vn = select i1 %vu, %Slot zeroinitializer, %Slot %v
  store %Slot %vn, %Slot* %p
  ret void
}
; t2_aunshift(a, v): v in front, every element one further on.
define internal void @t2_aunshift_d(%Array* %a, %Slot %v) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %n1 = add i64 %n, 1
  call void @t2_agrow(%Array* %a, i64 %n1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %from = getelementptr %Slot, %Slot* %els, i64 %im
  %e = load %Slot, %Slot* %from
  %to = getelementptr %Slot, %Slot* %els, i64 %i
  store %Slot %e, %Slot* %to
  br label %loop
done:
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vn = select i1 %vu, %Slot zeroinitializer, %Slot %v
  store %Slot %vn, %Slot* %els
  ret void
}
define internal %Slot @t2_aget_d(%Array* %a, i64 %i) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  %hi = icmp sge i64 %j, %n
  %out = or i1 %lo, %hi
  br i1 %out, label %undef, label %get
get:
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %v = load %Slot, %Slot* %p
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vr = select i1 %vu, %Slot zeroinitializer, %Slot %v   ; (an absent one is undef)
  ret %Slot %vr
undef:
  ret %Slot zeroinitializer
}
@lit_aset = private unnamed_addr constant [64 x i8] c"Modification of non-creatable array value attempted, subscript \00"
; HOLES: an element perl has not made (past a store beyond the end, or $#a
; grown) is ABSENT -- tag undef, payload 1. Every reader takes it for undef;
; aget and the stores make it a plain undef, so it never leaves its array.
; exists $a[i] of a plain array: in it, and not absent.
define internal i1 @t2_aexists_d(%Array* %a, i64 %i) {
entry:
  %n = call i64 @t2_alen_d(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  %hi = icmp sge i64 %j, %n
  %out = or i1 %lo, %hi
  br i1 %out, label %no, label %look
look:
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %v = load %Slot, %Slot* %p
  %t = extractvalue %Slot %v, 0
  %w = extractvalue %Slot %v, 1
  %ut = icmp eq i8 %t, 0
  %uw = icmp eq i64 %w, 1
  %absent = and i1 %ut, %uw
  %there = xor i1 %absent, true
  ret i1 %there
no:
  ret i1 false
}
; A TIED ARRAY\'S are its class\'s EXISTS and STORESIZE (n + 1); a negative
; index counts back from its FETCHSIZE, as perl\'s does. Both are reached through
; the container\'s metaobject (slots 18 and 19).
@lit_tm_storesize = private unnamed_addr constant [10 x i8] c"STORESIZE\00"
define internal i1 @t2_tie_aexists(%Array* %a, i64 %i) {
entry:
  %neg = icmp slt i64 %i, 0
  br i1 %neg, label %back, label %ask
back:
  %n = call i64 @t2_tie_alen(%Array* %a)
  %fromend = add i64 %i, %n
  br label %ask
ask:
  %j = phi i64 [ %i, %entry ], [ %fromend, %back ]
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %js = call %Slot @t2_box_i64(i64 %j)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_apush(%Array* %args, %Slot %js)
  %m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_exists, i64 0, i64 0), i64 6)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  %b = call i1 @t2_truth_slot(%Slot %r)
  ret i1 %b
}
define internal void @t2_tie_aset_len(%Array* %a, i64 %n) {
entry:
  %n1 = add i64 %n, 1
  %neg = icmp slt i64 %n1, 0
  %nl = select i1 %neg, i64 0, i64 %n1
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ns = call %Slot @t2_box_i64(i64 %nl)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_apush(%Array* %args, %Slot %ns)
  %m = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_tm_storesize, i64 0, i64 0), i64 9)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal i1 @t2_aexists(%Array* %a, i64 %i) {
  %f = call i8* @t2_vt(%Array* %a, i64 18)
  %fn = bitcast i8* %f to i1 (%Array*, i64)*
  %r = call i1 %fn(%Array* %a, i64 %i)
  ret i1 %r
}
define internal void @t2_aset_len(%Array* %a, i64 %n) {
  %f = call i8* @t2_vt(%Array* %a, i64 19)
  %fn = bitcast i8* %f to void (%Array*, i64)*
  call void %fn(%Array* %a, i64 %n)
  ret void
}
; $#a = n: n + 1 elements (none below -1); grown, the new ones are absent.
define internal void @t2_aset_len_d(%Array* %a, i64 %n) {
entry:
  %n1 = add i64 %n, 1
  %neg = icmp slt i64 %n1, 0
  %nl = select i1 %neg, i64 0, i64 %n1
  %len = call i64 @t2_alen_d(%Array* %a)
  %shrink = icmp sle i64 %nl, %len
  br i1 %shrink, label %cut, label %grow
cut:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %nl, i64* %lp
  ret void
grow:
  call void @t2_agrow(%Array* %a, i64 %nl)
  ret void
}
define internal void @t2_aset_d(%Array* %a, i64 %i, %Slot %v, i8* %at, i64 %atn) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fromend = add i64 %i, %n
  %j = select i1 %neg, i64 %fromend, i64 %i
  %lo = icmp slt i64 %j, 0
  br i1 %lo, label %die, label %set
set:
  %j1 = add i64 %j, 1
  call void @t2_agrow(%Array* %a, i64 %j1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %vt = extractvalue %Slot %v, 0
  %vu = icmp eq i8 %vt, 0
  %vn = select i1 %vu, %Slot zeroinitializer, %Slot %v
  store %Slot %vn, %Slot* %p
  ret void
die:
  %m = getelementptr [64 x i8], [64 x i8]* @lit_aset, i64 0, i64 0
  call i64 @write(i32 2, i8* %m, i64 63)
  %is = call %Str @t2_i64_str(i64 %i)
  %ip = extractvalue %Str %is, 0
  %in = extractvalue %Str %is, 1
  call i64 @write(i32 2, i8* %ip, i64 %in)
  call i64 @write(i32 2, i8* %at, i64 %atn)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
define internal %Slot @t2_apop_d(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %undef, label %pop
pop:
  %n1 = sub i64 %n, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %n1)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %n1, i64* %lp
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal %Slot @t2_ashift_d(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %undef, label %shift
shift:
  %v = call %Slot @t2_aget(%Array* %a, i64 0)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %d = bitcast %Slot* %els to i8*
  %s1 = getelementptr %Slot, %Slot* %els, i64 1
  %s = bitcast %Slot* %s1 to i8*
  %n1 = sub i64 %n, 1
  %bytes = mul i64 %n1, 16
  call i8* @memmove(i8* %d, i8* %s, i64 %bytes)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 %n1, i64* %lp
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal %Str @t2_join(%Str %sep, %Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %e = call %Str @t2_str(i8* null, i64 0)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %acc = phi %Str [ %e, %entry ], [ %acc2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %first = icmp eq i64 %i, 0
  %pre = call %Str @t2_concat(%Str %acc, %Str %sep)
  %acc1 = select i1 %first, %Str %acc, %Str %pre
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  %vs = call %Str @t2_slot_str(%Slot %v)
  %acc2 = call %Str @t2_concat(%Str %acc1, %Str %vs)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret %Str %acc
}
define internal i1 @t2_truth_i64(i64 %v) {
  %b = icmp ne i64 %v, 0
  ret i1 %b
}
define internal i1 @t2_truth_num(double %v) {
  %b = fcmp une double %v, 0.0
  ret i1 %b
}
define internal i1 @t2_truth_str(%Str %s) {
entry:
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %no, label %one
one:
  %is1 = icmp eq i64 %n, 1
  br i1 %is1, label %check, label %yes
check:
  %p = extractvalue %Str %s, 0
  %c = load i8, i8* %p
  %zero = icmp eq i8 %c, 48
  br i1 %zero, label %no, label %yes
yes:
  ret i1 1
no:
  ret i1 0
}
define internal i1 @t2_truth_slot(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 4, label %int
                               i8 2, label %num
                               i8 3, label %str
                               i8 5, label %ref
                               i8 6, label %ref
                               i8 8, label %ref
                               i8 9, label %ref ]
int:
  %bi = icmp ne i64 %v, 0
  ret i1 %bi
num:
  %d = bitcast i64 %v to double
  %bn = fcmp une double %d, 0.0
  ret i1 %bn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %bs = call i1 @t2_truth_str(%Str %sv)
  ret i1 %bs
undef:
  ret i1 0
ref:
  ret i1 1
}
; A HASH REFERENCE is a %Slot of tag 5 whose payload is an %Array of its
; pairs, key (a boxed Str) then value, in insertion order (perl\'s own order
; is not promised; keys/each are not this slice\'s).
declare i32 @memcmp(i8*, i8*, i64)
@msg_notahash = private unnamed_addr constant [75 x i8] c"chalk: refused at run time: a hash element read through no HASH reference\0A\00"
@lit_hash = private unnamed_addr constant [5 x i8] c"HASH\00"
@lit_array = private unnamed_addr constant [6 x i8] c"ARRAY\00"
@lit_code = private unnamed_addr constant [5 x i8] c"CODE\00"
@lit_scalar = private unnamed_addr constant [7 x i8] c"SCALAR\00"
@msg_notanarray = private unnamed_addr constant [78 x i8] c"chalk: refused at run time: an array element read through no ARRAY reference\0A\00"
@msg_refstr = private unnamed_addr constant [62 x i8] c"chalk: refused at run time: a reference read as a str or num\0A\00"
define internal void @t2_stop(i8* %m, i64 %n) {
  %w = call i64 @write(i32 2, i8* %m, i64 %n)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
define internal void @t2_stop_unless(i1 %ok, %Str %m) {
entry:
  br i1 %ok, label %yes, label %no
no:
  %p = extractvalue %Str %m, 0
  %n = extractvalue %Str %m, 1
  call void @t2_stop(i8* %p, i64 %n)
  unreachable
yes:
  ret void
}
define internal void @t2_refscalar() {
  call void @t2_stop(i8* getelementptr ([62 x i8], [62 x i8]* @msg_refstr, i64 0, i64 0), i64 61)
  unreachable
}
; A HASH\'S %Array: element 0 is the class a bless gave it (undef until),
; then key, value pairs.
define internal %Slot @t2_hnew() {
  %a = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %a, %Slot zeroinitializer)
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 5, i64 %i)
  ret %Slot %s
}
define internal %Array* @t2_harr(%Slot %h) {
entry:
  %t = extractvalue %Slot %h, 0
  %ok = icmp eq i8 %t, 5
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([75 x i8], [75 x i8]* @msg_notahash, i64 0, i64 0), i64 74)
  unreachable
yes:
  %v = extractvalue %Slot %h, 1
  %a = inttoptr i64 %v to %Array*
  ret %Array* %a
}
; t2_hfind(a, k) -> the index of k\'s key slot, or -1.
define internal i64 @t2_hfind(%Array* %a, %Str %k) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %kp = extractvalue %Str %k, 0
  %kl = extractvalue %Str %k, 1
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %ks = call %Slot @t2_aget(%Array* %a, i64 %i)
  %kstr = call %Str @t2_slot_str(%Slot %ks)
  %ol = extractvalue %Str %kstr, 1
  %samelen = icmp eq i64 %ol, %kl
  br i1 %samelen, label %cmp, label %next
cmp:
  %op = extractvalue %Str %kstr, 0
  %c = call i32 @memcmp(i8* %op, i8* %kp, i64 %kl)
  %eq = icmp eq i32 %c, 0
  br i1 %eq, label %found, label %next
next:
  %i2 = add i64 %i, 2
  br label %loop
found:
  ret i64 %i
none:
  ret i64 -1
}
@msg_blessnot = private unnamed_addr constant [78 x i8] c"chalk: refused at run time: a bless of what is not a hash or array reference\0A\00"
define internal %Slot @t2_bless(%Slot %h, %Str %c) {
entry:
  %t = extractvalue %Slot %h, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %ok = or i1 %ish, %isa
  br i1 %ok, label %set, label %other
other:
  %issc = icmp eq i8 %t, 9
  %iscd = icmp eq i8 %t, 8
  %side = or i1 %issc, %iscd
  br i1 %side, label %table, label %bad
table:
  %tb = call %Slot @t2_ghash(%Slot* @t2_blessings)
  %k = call %Str @t2_addr_key(%Slot %h)
  %tcs = call %Slot @t2_box_str(%Str %c)
  call void @t2_hset(%Slot %tb, %Str %k, %Slot %tcs)
  ret %Slot %h
bad:
  call void @t2_stop(i8* getelementptr ([78 x i8], [78 x i8]* @msg_blessnot, i64 0, i64 0), i64 77)
  unreachable
set:
  %cs = call %Slot @t2_box_str(%Str %c)
  %v = extractvalue %Slot %h, 1
  %a = inttoptr i64 %v to %Array*
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 4
  store %Slot %cs, %Slot* %cp
  ret %Slot %h
}
; t2_class_of(s) -> the class a hash or array reference was blessed into
; (a boxed Str), else undef.
define internal %Slot @t2_class_of(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %ok = or i1 %ish, %isa
  br i1 %ok, label %agg, label %other
agg:
  %v = extractvalue %Slot %s, 1
  %a = inttoptr i64 %v to %Array*
  %cp = getelementptr %Array, %Array* %a, i32 0, i32 4
  %c = load %Slot, %Slot* %cp
  ret %Slot %c
other:
  %issc = icmp eq i8 %t, 9
  %iscd = icmp eq i8 %t, 8
  %side = or i1 %issc, %iscd
  br i1 %side, label %table, label %none
table:
  %tb = call %Slot @t2_ghash(%Slot* @t2_blessings)
  %k = call %Str @t2_addr_key(%Slot %s)
  %tc = call %Slot @t2_hget(%Slot %tb, %Str %k)
  ret %Slot %tc
none:
  ret %Slot zeroinitializer
}
; A SCALAR OR CODE REFERENCE\'S CLASS: no header to hold it, so a table keyed
; by its address (t2_addr_key).
@t2_blessings = internal global %Slot zeroinitializer
define internal %Str @t2_addr_key(%Slot %s) {
  %a = extractvalue %Slot %s, 1
  %b = call %Slot @t2_box_i64(i64 %a)
  %k = call %Str @t2_slot_str(%Slot %b)
  ret %Str %k
}
; A SCALAR REFERENCE (`\$x`) is a %Slot of tag 9 whose payload is the
; variable\'s heap cell.
define internal %Slot @t2_sref(%Slot* %c) {
  %i = ptrtoint %Slot* %c to i64
  %s = call %Slot @t2_slot(i8 9, i64 %i)
  ret %Slot %s
}
@lit_sc_undef = private unnamed_addr constant [51 x i8] c"Can\'t use an undefined value as a SCALAR reference\00"
@lit_sc_not = private unnamed_addr constant [23 x i8] c"Not a SCALAR reference\00"
@lit_sc_str0 = private unnamed_addr constant [20 x i8] c"Can\'t use string (\22\00"
@lit_sc_str1 = private unnamed_addr constant [46 x i8] c"\22) as a SCALAR ref while \22strict refs\22 in use\00"
@lit_sc_more = private unnamed_addr constant [5 x i8] c"\22...\00"
@msg_symref = private unnamed_addr constant [65 x i8] c"chalk: refused at run time: a string as a reference (no strict)\0A\00"
; t2_sderef_cell(r, strict, at, n) -> the cell r refers to; null after
; perl\'s die (what r is named), a stop for a name without strict refs.
define internal %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
entry:
  %t = extractvalue %Slot %r, 0
  switch i8 %t, label %str [ i8 9, label %ok
                             i8 0, label %undef
                             i8 5, label %not
                             i8 6, label %not
                             i8 7, label %not
                             i8 8, label %not ]
ok:
  %v = extractvalue %Slot %r, 1
  %c = inttoptr i64 %v to %Slot*
  ret %Slot* %c
undef:
  br i1 %strict, label %undefdie, label %none
undefdie:
  %u = call %Str @t2_str(i8* getelementptr ([51 x i8], [51 x i8]* @lit_sc_undef, i64 0, i64 0), i64 50)
  br label %die
not:
  %nm = call %Str @t2_str(i8* getelementptr ([23 x i8], [23 x i8]* @lit_sc_not, i64 0, i64 0), i64 22)
  br label %die
str:
  br i1 %strict, label %strdie, label %sym
sym:
  %nm0 = call %Str @t2_slot_str(%Slot %r)
  %pks = call %Str @t2_str(i8* %pk, i64 %pkn)
  %cell = call %Slot* @t2_symref(%Str %nm0, %Str %pks)
  ret %Slot* %cell
strdie:
  %sv = call %Str @t2_slot_str(%Slot %r)
  %sl = extractvalue %Str %sv, 1
  %long = icmp ugt i64 %sl, 32
  %cut = select i1 %long, i64 32, i64 %sl
  %sp = extractvalue %Str %sv, 0
  %head = call %Str @t2_str(i8* %sp, i64 %cut)
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %head)
  %more = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_sc_more, i64 0, i64 0), i64 4)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %more)
  %p1b = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 0)
  %tail0 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_sc_str1, i64 0, i64 0), i64 45)
  %tail1 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_sc_str1, i64 0, i64 1), i64 44)
  %lp = select i1 %long, %Str %p2, %Str %p1
  %tl = select i1 %long, %Str %tail1, %Str %tail0
  %sm = call %Str @t2_concat(%Str %lp, %Str %tl)
  br label %die
die:
  %m0 = phi %Str [ %u, %undefdie ], [ %nm, %not ], [ %sm, %strdie ]
  %as = call %Str @t2_str(i8* %at, i64 %n)
  %m = call %Str @t2_concat(%Str %m0, %Str %as)
  call void @t2_die_unwind(%Str %m)
  ret %Slot* null
none:
  ret %Slot* null
}
; THE PROGRAM\'S PACKAGE SCALARS BY NAME ("main::x" -> a SCALAR reference to its
; global), for a string used as a reference without strict refs; one no one
; named is made on first use, as perl\'s. t2_symtab_init (the printer\'s) fills it.
@t2_symtab = internal global %Slot zeroinitializer
@t2_symtab_ready = internal global i1 0
@lit_colons = private unnamed_addr constant [3 x i8] c"::\00"
@lit_mainpk = private unnamed_addr constant [5 x i8] c"main\00"
define internal void @t2_symtab_add(i8* %p, i64 %n, %Slot* %g) {
  %t = call %Slot @t2_ghash(%Slot* @t2_symtab)
  %k = call %Str @t2_str(i8* %p, i64 %n)
  %s = call %Slot @t2_sref(%Slot* %g)
  call void @t2_hset(%Slot %t, %Str %k, %Slot %s)
  ret void
}
; t2_has_colons(s) -> whether s holds "::"
define internal i1 @t2_has_colons(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %last = sub i64 %n, 1
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %next ]
  %more = icmp slt i64 %i, %last
  br i1 %more, label %look, label %no
look:
  %a = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %a
  %i2 = add i64 %i, 1
  %b = getelementptr i8, i8* %p, i64 %i2
  %d = load i8, i8* %b
  %c1 = icmp eq i8 %c, 58
  %d1 = icmp eq i8 %d, 58
  %both = and i1 %c1, %d1
  br i1 %both, label %yes, label %next
next:
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
define internal %Slot* @t2_symref(%Str %name, %Str %pk) {
entry:
  %ready = load i1, i1* @t2_symtab_ready
  br i1 %ready, label %go, label %init
init:
  store i1 1, i1* @t2_symtab_ready
  call void @t2_symtab_init()
  br label %go
go:
  %q = call i1 @t2_has_colons(%Str %name)
  br i1 %q, label %qual, label %unq
qual:
  %np = extractvalue %Str %name, 0
  %c0 = load i8, i8* %np
  %lead = icmp eq i8 %c0, 58
  br i1 %lead, label %lead_main, label %have
lead_main:
  %m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_mainpk, i64 0, i64 0), i64 4)
  %ml = call %Str @t2_concat(%Str %m, %Str %name)
  br label %have
unq:
  %cc = call %Str @t2_str(i8* getelementptr ([3 x i8], [3 x i8]* @lit_colons, i64 0, i64 0), i64 2)
  %p1 = call %Str @t2_concat(%Str %pk, %Str %cc)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %name)
  br label %have
have:
  %full = phi %Str [ %name, %qual ], [ %ml, %lead_main ], [ %p2, %unq ]
  %t = call %Slot @t2_ghash(%Slot* @t2_symtab)
  %s = call %Slot @t2_hget(%Slot %t, %Str %full)
  %st = extractvalue %Slot %s, 0
  %found = icmp eq i8 %st, 9
  br i1 %found, label %old, label %new
old:
  %v = extractvalue %Slot %s, 1
  %oc = inttoptr i64 %v to %Slot*
  ret %Slot* %oc
new:
  %mem = call i8* @malloc(i64 16)
  %nc = bitcast i8* %mem to %Slot*
  store %Slot zeroinitializer, %Slot* %nc
  %ns = call %Slot @t2_sref(%Slot* %nc)
  call void @t2_hset(%Slot %t, %Str %full, %Slot %ns)
  ret %Slot* %nc
}
define internal %Slot @t2_sderef(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
  %c = call %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn)
  %z = icmp eq %Slot* %c, null
  br i1 %z, label %undef, label %load
undef:
  ret %Slot zeroinitializer
load:
  %v = load %Slot, %Slot* %c
  ret %Slot %v
}
@msg_sstore_undef = private unnamed_addr constant [75 x i8] c"chalk: refused at run time: a store through an undefined scalar reference\0A\00"
define internal void @t2_sstore(%Slot %r, %Slot %v, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn) {
entry:
  %t = extractvalue %Slot %r, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %viv, label %go
viv:
  call void @t2_stop(i8* getelementptr ([75 x i8], [75 x i8]* @msg_sstore_undef, i64 0, i64 0), i64 74)
  unreachable
go:
  %c = call %Slot* @t2_sderef_cell(%Slot %r, i1 %strict, i8* %at, i64 %n, i8* %pk, i64 %pkn)
  %z = icmp eq %Slot* %c, null
  br i1 %z, label %done, label %chk
chk:
  %ro = call i1 @t2_is_ro(%Slot* %c)
  br i1 %ro, label %rodie, label %st
rodie:
  %m0 = call %Str @t2_str(i8* getelementptr ([44 x i8], [44 x i8]* @lit_ro, i64 0, i64 0), i64 43)
  %as = call %Str @t2_str(i8* %at, i64 %n)
  %m = call %Str @t2_concat(%Str %m0, %Str %as)
  call void @t2_die_unwind(%Str %m)
  br label %done
st:
  store %Slot %v, %Slot* %c
  br label %done
done:
  ret void
}
; t2_reftype(s) -> perl\'s ref(): an object\'s class, HASH, or "" for no reference.
define internal %Str @t2_reftype(%Slot %s) {
entry:
  %c = call %Slot @t2_class_of(%Slot %s)
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %plain
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  ret %Str %cn
plain:
  %b = call %Str @t2_basetype(%Slot %s)
  ret %Str %b
}
; t2_basetype(s) -> what s refers to, blessed or not: HASH, ARRAY, CODE,
; SCALAR, or "" for no reference.
define internal %Str @t2_basetype(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %none [ i8 5, label %hash
                              i8 6, label %arr
                              i8 8, label %code
                              i8 9, label %sc ]
hash:
  %h = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 4)
  ret %Str %h
arr:
  %a = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_array, i64 0, i64 0), i64 5)
  ret %Str %a
code:
  %k = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_code, i64 0, i64 0), i64 4)
  ret %Str %k
sc:
  ; (a reference to a scalar that holds a reference is a REF: `ref \\$r`)
  %ci = extractvalue %Slot %s, 1
  %cp = inttoptr i64 %ci to %Slot*
  %cv = load %Slot, %Slot* %cp
  %cvt = extractvalue %Slot %cv, 0
  %clo = icmp uge i8 %cvt, 5
  %chi = icmp ule i8 %cvt, 9
  %toref = and i1 %clo, %chi
  br i1 %toref, label %rr, label %plain_sc
rr:
  %rq = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_kind_ref, i64 0, i64 0), i64 3)
  ret %Str %rq
plain_sc:
  %q = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_scalar, i64 0, i64 0), i64 6)
  ret %Str %q
none:
  %e = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_hash, i64 0, i64 0), i64 0)
  ret %Str %e
}
; t2_referent_type(s) -> Scalar::Util\'s reftype: what s refers to, its class
; aside (HASH, ARRAY, CODE, SCALAR, REF; REGEXP for a qr//), undef for what
; is no reference.
@lit_kind_regexp = private unnamed_addr constant [7 x i8] c"REGEXP\00"
define internal %Slot @t2_referent_type(%Slot %s) {
entry:
  %b = call %Str @t2_basetype(%Slot %s)
  %n = extractvalue %Str %b, 1
  %none = icmp eq i64 %n, 0
  br i1 %none, label %undef, label %ref
undef:
  ret %Slot zeroinitializer
ref:
  %c = call %Slot @t2_class_of(%Slot %s)
  %ct = extractvalue %Slot %c, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %plain
obj:
  %cn = call %Str @t2_slot_str(%Slot %c)
  %rxn = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_regexp, i64 0, i64 0), i64 6)
  %rxc = call i64 @t2_strcmp(%Str %cn, %Str %rxn)
  %isrx = icmp eq i64 %rxc, 0
  br i1 %isrx, label %rx, label %plain
rx:
  %rs = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_kind_regexp, i64 0, i64 0), i64 6)
  %rb = call %Slot @t2_box_str(%Str %rs)
  ret %Slot %rb
plain:
  %pb = call %Slot @t2_box_str(%Str %b)
  ret %Slot %pb
}
@t2_stashes = internal global %Slot zeroinitializer
@lit_isa = private unnamed_addr constant [5 x i8] c"@ISA\00"
@lit_cm = private unnamed_addr constant [20 x i8] c"Can\'t call method \22\00"
@lit_undefv = private unnamed_addr constant [24 x i8] c"\22 on an undefined value\00"
@lit_unbl = private unnamed_addr constant [25 x i8] c"\22 on unblessed reference\00"
@lit_nopkg = private unnamed_addr constant [40 x i8] c"\22 without a package or object reference\00"
@lit_lom = private unnamed_addr constant [29 x i8] c"Can\'t locate object method \22\00"
@lit_via = private unnamed_addr constant [16 x i8] c"\22 via package \22\00"
@lit_q = private unnamed_addr constant [2 x i8] c"\22\00"
@lit_forgot = private unnamed_addr constant [32 x i8] c"\22 (perhaps you forgot to load \22\00"
@lit_qp = private unnamed_addr constant [4 x i8] c"\22?)\00"
@msg_arity = private unnamed_addr constant [68 x i8] c"chalk: refused at run time: a call of a signature of another arity\0A\00"
define internal %Slot @t2_stash_table() {
entry:
  %t = load %Slot, %Slot* @t2_stashes
  %tag = extractvalue %Slot %t, 0
  %made = icmp eq i8 %tag, 5
  br i1 %made, label %have, label %make
make:
  %n = call %Slot @t2_hnew()
  store %Slot %n, %Slot* @t2_stashes
  ret %Slot %n
have:
  ret %Slot %t
}
@t2_want = internal global i1 0   ; the caller\'s context: 1 a list
@t2_argc = internal global i32 0
@t2_argvp = internal global i8** null
@t2_ARGV = internal global %Array* null
define internal void @t2_save_args(i32 %c, i8** %v) {
  store i32 %c, i32* @t2_argc
  store i8** %v, i8*** @t2_argvp
  ; perl\'s $@ starts "" (defined)
  %e = call %Str @t2_str(i8* null, i64 0)
  %es = call %Slot @t2_box_str(%Str %e)
  store %Slot %es, %Slot* @t2_err
  ret void
}
; t2_argv() -> @ARGV: argv[1..] as strings, made once.
define internal %Array* @t2_argv() {
entry:
  %have = load %Array*, %Array** @t2_ARGV
  %made = icmp ne %Array* %have, null
  br i1 %made, label %done, label %make
make:
  %a = call %Array* @t2_new_array()
  %c32 = load i32, i32* @t2_argc
  %c = sext i32 %c32 to i64
  %v = load i8**, i8*** @t2_argvp
  br label %loop
loop:
  %i = phi i64 [ 1, %make ], [ %i2, %body ]
  %more = icmp slt i64 %i, %c
  br i1 %more, label %body, label %store
body:
  %pp = getelementptr i8*, i8** %v, i64 %i
  %p = load i8*, i8** %pp
  %n = call i64 @strlen(i8* %p)
  %s = call %Str @t2_str(i8* %p, i64 %n)
  %sl = call %Slot @t2_box_str(%Str %s)
  call void @t2_apush(%Array* %a, %Slot %sl)
  %i2 = add i64 %i, 1
  br label %loop
store:
  store %Array* %a, %Array** @t2_ARGV
  ret %Array* %a
done:
  ret %Array* %have
}
define internal %Slot @t2_aref(%Array* %a) {
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 6, i64 %i)
  ret %Slot %s
}
; t2_aderef_r(s) -> for an element read through it: the array s refers to; an
; undef s reads as an empty one (perl\'s makes it), anything else stops.
define internal %Array* @t2_aderef_r(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  %e = call %Array* @t2_new_array()
  ret %Array* %e
go:
  %a = call %Array* @t2_aderef(%Slot %s)
  ret %Array* %a
}
define internal %Array* @t2_aderef(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ok = icmp eq i8 %t, 6
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([78 x i8], [78 x i8]* @msg_notanarray, i64 0, i64 0), i64 77)
  unreachable
yes:
  %v = extractvalue %Slot %s, 1
  %a = inttoptr i64 %v to %Array*
  ret %Array* %a
}
; t2_aderef_whole(s, strict, at, n) -> for the WHOLE array read through s
; where B::SoN says perl may die (`@$x > 0`, `"@$x"`, `my @c = @$x`): the
; array s refers to; an undef s dies under strict refs ("Can\'t use an
; undefined value as an ARRAY reference at FILE line N.") and reads as an
; empty one without (perl leaves it undef); another reference dies ("Not an
; ARRAY reference"); a string dies under strict refs, and without it names a
; package array: a stop. After a die an eval catches, an empty array.
@lit_av_undef = private unnamed_addr constant [51 x i8] c"Can\'t use an undefined value as an ARRAY reference\00"
@lit_av_not = private unnamed_addr constant [23 x i8] c"Not an ARRAY reference\00"
@lit_av_str1 = private unnamed_addr constant [46 x i8] c"\22) as an ARRAY ref while \22strict refs\22 in use\00"
define internal %Array* @t2_aderef_whole(%Slot %s, i1 %strict, i8* %at, i64 %n) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %str [ i8 6, label %ok
                             i8 0, label %undef
                             i8 5, label %not
                             i8 7, label %not
                             i8 8, label %not
                             i8 9, label %not ]
ok:
  %a = call %Array* @t2_aderef(%Slot %s)
  ret %Array* %a
undef:
  br i1 %strict, label %undefdie, label %none
none:
  %e = call %Array* @t2_new_array()
  ret %Array* %e
undefdie:
  %u = call %Str @t2_str(i8* getelementptr ([51 x i8], [51 x i8]* @lit_av_undef, i64 0, i64 0), i64 50)
  br label %die
not:
  %nm = call %Str @t2_str(i8* getelementptr ([23 x i8], [23 x i8]* @lit_av_not, i64 0, i64 0), i64 22)
  br label %die
str:
  br i1 %strict, label %strdie, label %sym
sym:
  call void @t2_stop(i8* getelementptr ([65 x i8], [65 x i8]* @msg_symref, i64 0, i64 0), i64 64)
  unreachable
strdie:
  %sv = call %Str @t2_slot_str(%Slot %s)
  %sl = extractvalue %Str %sv, 1
  %long = icmp ugt i64 %sl, 32
  %cut = select i1 %long, i64 32, i64 %sl
  %sp = extractvalue %Str %sv, 0
  %head = call %Str @t2_str(i8* %sp, i64 %cut)
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %head)
  %more = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_sc_more, i64 0, i64 0), i64 4)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %more)
  %tail0 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_av_str1, i64 0, i64 0), i64 45)
  %tail1 = call %Str @t2_str(i8* getelementptr ([46 x i8], [46 x i8]* @lit_av_str1, i64 0, i64 1), i64 44)
  %lp = select i1 %long, %Str %p2, %Str %p1
  %tl = select i1 %long, %Str %tail1, %Str %tail0
  %sm = call %Str @t2_concat(%Str %lp, %Str %tl)
  br label %die
die:
  %m0 = phi %Str [ %u, %undefdie ], [ %nm, %not ], [ %sm, %strdie ]
  %as = call %Str @t2_str(i8* %at, i64 %n)
  %m = call %Str @t2_concat(%Str %m0, %Str %as)
  call void @t2_die_unwind(%Str %m)
  %e2 = call %Array* @t2_new_array()
  ret %Array* %e2
}
; t2_hderef_whole(s, strict, at, n) -> for the WHOLE hash read through s
; where B::SoN says perl may die (`my %c = %$h`, `%$h ? 1 : 0`): s, a hash
; reference; an undef s dies under strict refs ("Can\'t use an undefined value
; as a HASH reference at FILE line N.") and is read as an empty one without;
; another reference dies ("Not a HASH reference"); a string dies under strict
; refs, and without it names a package hash: a stop. After a die an eval
; catches, undef.
@lit_hv_undef = private unnamed_addr constant [49 x i8] c"Can\'t use an undefined value as a HASH reference\00"
@lit_hv_not = private unnamed_addr constant [21 x i8] c"Not a HASH reference\00"
@lit_hv_str1 = private unnamed_addr constant [44 x i8] c"\22) as a HASH ref while \22strict refs\22 in use\00"
define internal %Slot @t2_hderef_whole(%Slot %s, i1 %strict, i8* %at, i64 %n) {
entry:
  %t = extractvalue %Slot %s, 0
  switch i8 %t, label %str [ i8 5, label %ok
                             i8 0, label %undef
                             i8 6, label %not
                             i8 7, label %not
                             i8 8, label %not
                             i8 9, label %not ]
ok:
  ret %Slot %s
undef:
  br i1 %strict, label %undefdie, label %ok
undefdie:
  %u = call %Str @t2_str(i8* getelementptr ([49 x i8], [49 x i8]* @lit_hv_undef, i64 0, i64 0), i64 48)
  br label %die
not:
  %nm = call %Str @t2_str(i8* getelementptr ([21 x i8], [21 x i8]* @lit_hv_not, i64 0, i64 0), i64 20)
  br label %die
str:
  br i1 %strict, label %strdie, label %sym
sym:
  call void @t2_stop(i8* getelementptr ([65 x i8], [65 x i8]* @msg_symref, i64 0, i64 0), i64 64)
  unreachable
strdie:
  %sv = call %Str @t2_slot_str(%Slot %s)
  %sl = extractvalue %Str %sv, 1
  %long = icmp ugt i64 %sl, 32
  %cut = select i1 %long, i64 32, i64 %sl
  %sp = extractvalue %Str %sv, 0
  %head = call %Str @t2_str(i8* %sp, i64 %cut)
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_sc_str0, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %head)
  %more = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_sc_more, i64 0, i64 0), i64 4)
  %p2 = call %Str @t2_concat(%Str %p1, %Str %more)
  %tail0 = call %Str @t2_str(i8* getelementptr ([44 x i8], [44 x i8]* @lit_hv_str1, i64 0, i64 0), i64 43)
  %tail1 = call %Str @t2_str(i8* getelementptr ([44 x i8], [44 x i8]* @lit_hv_str1, i64 0, i64 1), i64 42)
  %lp = select i1 %long, %Str %p2, %Str %p1
  %tl = select i1 %long, %Str %tail1, %Str %tail0
  %sm = call %Str @t2_concat(%Str %lp, %Str %tl)
  br label %die
die:
  %m0 = phi %Str [ %u, %undefdie ], [ %nm, %not ], [ %sm, %strdie ]
  %as = call %Str @t2_str(i8* %at, i64 %n)
  %m = call %Str @t2_concat(%Str %m0, %Str %as)
  call void @t2_die_unwind(%Str %m)
  ret %Slot zeroinitializer
}
@msg_oneof = private unnamed_addr constant [88 x i8] c"chalk: refused at run time: a list of other than one value passed as one argument (T2)\0A\00"
; t2_one_of(a) -> a\'s one element; a stop when it has another number.
define internal %Slot @t2_one_of(%Array* %a) {
entry:
  %n = call i64 @t2_alen(%Array* %a)
  %one = icmp eq i64 %n, 1
  br i1 %one, label %ok, label %bad
ok:
  %v = call %Slot @t2_aget(%Array* %a, i64 0)
  ret %Slot %v
bad:
  call void @t2_stop(i8* getelementptr ([88 x i8], [88 x i8]* @msg_oneof, i64 0, i64 0), i64 87)
  unreachable
}
; t2_list_of(v, want) -> in a list context a reference to a list of v; else v.
define internal %Slot @t2_list_of(%Slot %v, i1 %w) {
entry:
  br i1 %w, label %list, label %one
list:
  %a = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %a, %Slot %v)
  %r = call %Slot @t2_aref(%Array* %a)
  ret %Slot %r
one:
  ret %Slot %v
}
; CLOSURES: a captured variable\'s storage on the heap; a code value (tag 8)
; points at {its function, its cells}.
; A LITERAL\'S CELL, READ-ONLY (`\0`, `\"x"`: perl\'s reference is to the
; constant itself, one per site): one of a pool, a store through which dies.
@t2_ro_pool = internal global [256 x %Slot] zeroinitializer
define internal i1 @t2_is_ro(%Slot* %c) {
  %p = ptrtoint %Slot* %c to i64
  %lo = ptrtoint [256 x %Slot]* @t2_ro_pool to i64
  %hi = ptrtoint %Slot* getelementptr ([256 x %Slot], [256 x %Slot]* @t2_ro_pool, i64 1, i64 0) to i64
  %a = icmp uge i64 %p, %lo
  %b = icmp ult i64 %p, %hi
  %r = and i1 %a, %b
  ret i1 %r
}
define internal %Slot* @t2_cell_new() {
  %m = call i8* @malloc(i64 16)
  %c = bitcast i8* %m to %Slot*
  store %Slot zeroinitializer, %Slot* %c
  ret %Slot* %c
}
define internal %Slot** @t2_env_new(i64 %n) {
  %b = mul i64 %n, 8
  %b1 = add i64 %b, 8
  %m = call i8* @malloc(i64 %b1)
  %e = bitcast i8* %m to %Slot**
  ret %Slot** %e
}
define internal void @t2_env_set(%Slot** %e, i64 %i, %Slot* %c) {
  %p = getelementptr %Slot*, %Slot** %e, i64 %i
  store %Slot* %c, %Slot** %p
  ret void
}
define internal %Slot* @t2_env_get(%Slot** %e, i64 %i) {
  %p = getelementptr %Slot*, %Slot** %e, i64 %i
  %c = load %Slot*, %Slot** %p
  ret %Slot* %c
}
define internal %Slot @t2_code_new(i8* %f, %Slot** %e) {
  %m = call i8* @malloc(i64 16)
  %pf = bitcast i8* %m to i8**
  store i8* %f, i8** %pf
  %pe0 = getelementptr i8*, i8** %pf, i64 1
  %pe = bitcast i8** %pe0 to %Slot***
  store %Slot** %e, %Slot*** %pe
  %i = ptrtoint i8* %m to i64
  %s = call %Slot @t2_slot(i8 8, i64 %i)
  ret %Slot %s
}
@msg_notcode = private unnamed_addr constant [69 x i8] c"chalk: refused at run time: a call of what is not a code value (T2)\0A\00"
define internal i8** @t2_code_of(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %ok = icmp eq i8 %t, 8
  br i1 %ok, label %yes, label %no
no:
  call void @t2_stop(i8* getelementptr ([69 x i8], [69 x i8]* @msg_notcode, i64 0, i64 0), i64 68)
  unreachable
yes:
  %v = extractvalue %Slot %s, 1
  %p = inttoptr i64 %v to i8**
  ret i8** %p
}
define internal i8* @t2_code_fn(%Slot %s) {
  %p = call i8** @t2_code_of(%Slot %s)
  %f = load i8*, i8** %p
  ret i8* %f
}
define internal %Slot** @t2_code_env(%Slot %s) {
  %p = call i8** @t2_code_of(%Slot %s)
  %pe0 = getelementptr i8*, i8** %p, i64 1
  %pe = bitcast i8** %pe0 to %Slot***
  %e = load %Slot**, %Slot*** %pe
  ret %Slot** %e
}
; t2_die(msg, at): perl\'s uncaught die -- the message to STDERR, `at` (" at
; FILE line N.\n") after it unless it ends in a newline; exit 255.
@lit_died = private unnamed_addr constant [5 x i8] c"Died\00"
define internal %Str @t2_die_msg(%Str %m, %Str %at) {
entry:
  %n = extractvalue %Str %m, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %died, label %last
died:
  ; die "" is "Died at FILE line N."
  %dm = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_died, i64 0, i64 0), i64 4)
  %dr = call %Str @t2_concat(%Str %dm, %Str %at)
  ret %Str %dr
last:
  %p = extractvalue %Str %m, 0
  %li = sub i64 %n, 1
  %lp = getelementptr i8, i8* %p, i64 %li
  %lc = load i8, i8* %lp
  %nl = icmp eq i8 %lc, 10
  br i1 %nl, label %done, label %addat
addat:
  %r = call %Str @t2_concat(%Str %m, %Str %at)
  ret %Str %r
done:
  ret %Str %m
}
; t2_die(msg): the __DIE__ handler first (t2_die_hook), then perl\'s uncaught die.
define internal void @t2_die(%Str %m0) {
  %m = call %Str @t2_die_hook(%Str %m0)
  call void @t2_die_raw(%Str %m)
  unreachable
}
define internal void @t2_die_raw(%Str %m) {
  %p = extractvalue %Str %m, 0
  %n = extractvalue %Str %m, 1
  call i64 @write(i32 2, i8* %p, i64 %n)
  call void @t2_run_ends()
  call void @exit(i32 255)
  unreachable
}
; EVAL: $@ (@t2_err), the evals open at run time, and the dying flag a die
; in a sub sets for its callers to unwind by.
@t2_err = internal global %Slot zeroinitializer
@t2_eval_depth = internal global i64 0
@t2_dying = internal global i1 0
define internal void @t2_set_err(%Str %m) {
  %s = call %Slot @t2_box_str(%Str %m)
  store %Slot %s, %Slot* @t2_err
  ret void
}
define internal void @t2_eval_enter() {
  %d = load i64, i64* @t2_eval_depth
  %d1 = add i64 %d, 1
  store i64 %d1, i64* @t2_eval_depth
  ret void
}
define internal void @t2_eval_leave() {
  %d = load i64, i64* @t2_eval_depth
  %d1 = sub i64 %d, 1
  store i64 %d1, i64* @t2_eval_depth
  ret void
}
; A DIE OF A VALUE that may be a reference (wire v2\'s `eval` profile): what
; it leaves in $@ -- a reference as itself, anything else as its message, with
; " at FILE line N.\n" where it ends in no newline (t2_die_value) -- stored
; there in an eval here (t2_set_err_slot), or as t2_die_unwind does up the
; calls; uncaught, its string to STDERR.
define internal %Slot @t2_die_value(%Slot %v, %Str %at) {
entry:
  %t = extractvalue %Slot %v, 0
  switch i8 %t, label %str [ i8 5, label %ref
                             i8 6, label %ref
                             i8 8, label %ref
                             i8 9, label %ref ]
ref:
  ret %Slot %v
str:
  %s = call %Str @t2_slot_str(%Slot %v)
  %m = call %Str @t2_die_msg(%Str %s, %Str %at)
  %b = call %Slot @t2_box_str(%Str %m)
  ret %Slot %b
}
define internal void @t2_set_err_slot(%Slot %v) {
  store %Slot %v, %Slot* @t2_err
  ret void
}
define internal void @t2_die_unwind_slot(%Slot %v) {
entry:
  %d = load i64, i64* @t2_eval_depth
  %open = icmp sgt i64 %d, 0
  br i1 %open, label %catch, label %exit
catch:
  store %Slot %v, %Slot* @t2_err
  store i1 1, i1* @t2_dying
  ret void
exit:
  %m = call %Str @t2_slot_str(%Slot %v)
  call void @t2_die_raw(%Str %m)
  unreachable
}
define internal void @t2_die_slot(%Slot %v) {
  %m = call %Str @t2_slot_str(%Slot %v)
  call void @t2_die_raw(%Str %m)
  unreachable
}
define internal void @t2_die_unwind(%Str %m0) {
entry:
  %m = call %Str @t2_die_hook(%Str %m0)
  %d = load i64, i64* @t2_eval_depth
  %open = icmp sgt i64 %d, 0
  br i1 %open, label %catch, label %exit
catch:
  call void @t2_set_err(%Str %m)
  store i1 1, i1* @t2_dying
  ret void
exit:
  call void @t2_die_raw(%Str %m)
  unreachable
}
; THE HANDLER TABLE (%SIG): @t2_sig holds %SIG\'s hash where the program uses
; %SIG -- its metaobject Chalk::Impl::SIG\'s instance, which holds the
; handlers -- else nothing, and no handler is ever set. warn and die ask it.
@t2_sig = internal global %Slot zeroinitializer
@t2_hooking = internal global i1 0
@lit_h_warn = private unnamed_addr constant [9 x i8] c"__WARN__\00"
@lit_h_die = private unnamed_addr constant [8 x i8] c"__DIE__\00"
@lit_h_default = private unnamed_addr constant [8 x i8] c"DEFAULT\00"
@lit_h_ignore = private unnamed_addr constant [7 x i8] c"IGNORE\00"
@msg_h_named = private unnamed_addr constant [101 x i8] c"chalk: refused at run time: a %SIG handler other than a code value (a sub by its name, a reference)\0A\00"
@msg_warn_empty = private unnamed_addr constant [103 x i8] c"chalk: refused at run time: a warn of an empty message (perl warns of $@, or that something is wrong)\0A\00"
define internal void @t2_sig_set(%Slot %h) {
  store %Slot %h, %Slot* @t2_sig
  ret void
}
; t2_sig_handler(name) -> the code value %SIG holds for name, or undef where
; none is set (no %SIG, undef, "", DEFAULT, IGNORE -- which for __WARN__ and
; __DIE__ is perl\'s default too). A sub named by a string: a stop.
define internal %Slot @t2_sig_handler(%Str %k) {
entry:
  %h = load %Slot, %Slot* @t2_sig
  %ht = extractvalue %Slot %h, 0
  %has = icmp eq i8 %ht, 5
  br i1 %has, label %look, label %none
look:
  %v = call %Slot @t2_hget(%Slot %h, %Str %k)
  %t = extractvalue %Slot %v, 0
  switch i8 %t, label %named [ i8 8, label %code
                               i8 0, label %none
                               i8 3, label %str ]
code:
  ret %Slot %v
str:
  %s = call %Str @t2_slot_str(%Slot %v)
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %none, label %words
words:
  %dflt = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_h_default, i64 0, i64 0), i64 7)
  %c1 = call i64 @t2_strcmp(%Str %s, %Str %dflt)
  %is1 = icmp eq i64 %c1, 0
  %ign = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_h_ignore, i64 0, i64 0), i64 6)
  %c2 = call i64 @t2_strcmp(%Str %s, %Str %ign)
  %is2 = icmp eq i64 %c2, 0
  %plain = or i1 %is1, %is2
  br i1 %plain, label %none, label %named
named:
  call void @t2_stop(i8* getelementptr ([101 x i8], [101 x i8]* @msg_h_named, i64 0, i64 0), i64 100)
  unreachable
none:
  ret %Slot zeroinitializer
}
; t2_call_handler(code, msg): a handler called with the message, as perl calls it.
define internal void @t2_call_handler(%Slot %c, %Str %m) {
  %args = call %Array* @t2_new_array()
  %ms = call %Slot @t2_box_str(%Str %m)
  call void @t2_apush(%Array* %args, %Slot %ms)
  %f = call i8* @t2_code_fn(%Slot %c)
  %e = call %Slot** @t2_code_env(%Slot %c)
  %fn = bitcast i8* %f to %Slot (%Array*, %Slot**)*
  %w = load i1, i1* @t2_want
  store i1 0, i1* @t2_want
  %r = call %Slot %fn(%Array* %args, %Slot** %e)
  store i1 %w, i1* @t2_want
  ret void
}
; t2_warn(msg, at) -> 1: perl\'s warn -- its message (" at FILE line N.\n",
; the site B::SoN gives the warn, added where it does not end in a newline)
; to its __WARN__ handler, else to STDERR. An empty message (perl\'s is $@\'s,
; or "Warning: something\'s wrong"): a stop.
define internal %Slot @t2_warn(%Str %m0, %Str %at) {
entry:
  %n = extractvalue %Str %m0, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %none, label %last
none:
  call void @t2_stop(i8* getelementptr ([103 x i8], [103 x i8]* @msg_warn_empty, i64 0, i64 0), i64 102)
  unreachable
last:
  %p = extractvalue %Str %m0, 0
  %li = sub i64 %n, 1
  %lp = getelementptr i8, i8* %p, i64 %li
  %lc = load i8, i8* %lp
  %nl = icmp eq i8 %lc, 10
  br i1 %nl, label %go, label %addat
addat:
  %ma = call %Str @t2_concat(%Str %m0, %Str %at)
  br label %go
go:
  %m = phi %Str [ %m0, %last ], [ %ma, %addat ]
  %k = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_h_warn, i64 0, i64 0), i64 8)
  %h = call %Slot @t2_sig_handler(%Str %k)
  %t = extractvalue %Slot %h, 0
  %code = icmp eq i8 %t, 8
  br i1 %code, label %call, label %print
call:
  call void @t2_call_handler(%Slot %h, %Str %m)
  br label %done
print:
  call void @t2_eprint(%Str %m)
  br label %done
done:
  %one = call %Slot @t2_slot(i8 1, i64 1)
  ret %Slot %one
}
; t2_die_hook(msg) -> the message a die dies with: its __DIE__ handler is
; called with it first (not again while it runs, as perl\'s); a handler that
; dies (an eval open: the dying flag) makes its own message the one.
define internal %Str @t2_die_hook(%Str %m) {
entry:
  %busy = load i1, i1* @t2_hooking
  br i1 %busy, label %plain, label %look
look:
  %k = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_h_die, i64 0, i64 0), i64 7)
  %h = call %Slot @t2_sig_handler(%Str %k)
  %t = extractvalue %Slot %h, 0
  %code = icmp eq i8 %t, 8
  br i1 %code, label %call, label %plain
call:
  store i1 1, i1* @t2_hooking
  call void @t2_call_handler(%Slot %h, %Str %m)
  store i1 0, i1* @t2_hooking
  %d = load i1, i1* @t2_dying
  br i1 %d, label %replaced, label %plain
replaced:
  store i1 0, i1* @t2_dying
  %e = load %Slot, %Slot* @t2_err
  %es = call %Str @t2_slot_str(%Slot %e)
  ret %Str %es
plain:
  ret %Str %m
}
define internal void @t2_apush_if(%Array* %a, %Slot %v, i1 %c) {
entry:
  br i1 %c, label %push, label %done
push:
  call void @t2_apush(%Array* %a, %Slot %v)
  br label %done
done:
  ret void
}
define internal void @t2_aappend_d(%Array* %d, %Array* %s) {
entry:
  %n = call i64 @t2_alen(%Array* %s)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %s, i64 %i)
  call void @t2_apush(%Array* %d, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret void
}
; t2_slot_length(s) -> perl\'s length of a scalar: undef for undef.
define internal %Slot @t2_slot_length(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %len
undef:
  ret %Slot zeroinitializer
len:
  %str = call %Str @t2_slot_str(%Slot %s)
  %n = extractvalue %Str %str, 1
  %r = call %Slot @t2_box_i64(i64 %n)
  ret %Slot %r
}
@msg_caseascii = private unnamed_addr constant [71 x i8] c"chalk: refused at run time: a case change of a string past ASCII (T2)\0A\00"
; t2_strcase(s, mode) -> s in ASCII case: 0 uc, 1 lc, 2 ucfirst, 3 lcfirst.
define internal %Str @t2_strcase(%Str %s, i64 %mode) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %cap = add i64 %n, 1
  %buf = call i8* @malloc(i64 %cap)
  %up = icmp eq i64 %mode, 0
  %up1 = icmp eq i64 %mode, 2
  %toup = or i1 %up, %up1
  %first = icmp sge i64 %mode, 2
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %put ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %sp = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %sp
  ; A BYTE PAST ASCII: perl\'s case of it depends on how it was read -- a stop.
  %high = icmp slt i8 %c, 0
  br i1 %high, label %past, label %ascii
past:
  call void @t2_stop(i8* getelementptr ([71 x i8], [71 x i8]* @msg_caseascii, i64 0, i64 0), i64 70)
  unreachable
ascii:
  %notfirst = icmp ne i64 %i, 0
  %keep = and i1 %first, %notfirst
  br i1 %keep, label %put0, label %conv
conv:
  br i1 %toup, label %upper, label %lower
upper:
  %isl = icmp uge i8 %c, 97
  %isl2 = icmp ule i8 %c, 122
  %lw = and i1 %isl, %isl2
  %cu = sub i8 %c, 32
  %ru = select i1 %lw, i8 %cu, i8 %c
  br label %put
lower:
  %isu = icmp uge i8 %c, 65
  %isu2 = icmp ule i8 %c, 90
  %uw = and i1 %isu, %isu2
  %cl = add i8 %c, 32
  %rl = select i1 %uw, i8 %cl, i8 %c
  br label %put
put0:
  br label %put
put:
  %r = phi i8 [ %ru, %upper ], [ %rl, %lower ], [ %c, %put0 ]
  %dp = getelementptr i8, i8* %buf, i64 %i
  store i8 %r, i8* %dp
  %i2 = add i64 %i, 1
  br label %loop
done:
  %out = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %out
}
; t2_strcmp(x, y) -> perl\'s cmp: -1, 0 or 1, bytewise, a prefix first.
define internal i64 @t2_strcmp(%Str %x, %Str %y) {
entry:
  %xp = extractvalue %Str %x, 0
  %xl = extractvalue %Str %x, 1
  %yp = extractvalue %Str %y, 0
  %yl = extractvalue %Str %y, 1
  %short = icmp slt i64 %xl, %yl
  %m = select i1 %short, i64 %xl, i64 %yl
  %r = call i32 @memcmp(i8* %xp, i8* %yp, i64 %m)
  %neg = icmp slt i32 %r, 0
  %pos = icmp sgt i32 %r, 0
  br i1 %neg, label %lt, label %notlt
notlt:
  br i1 %pos, label %gt, label %bylen
bylen:
  br i1 %short, label %lt, label %notshort
notshort:
  %longer = icmp sgt i64 %xl, %yl
  br i1 %longer, label %gt, label %eq
lt:
  ret i64 -1
gt:
  ret i64 1
eq:
  ret i64 0
}
; t2_stash(c) -> c\'s stash, made empty if c has none yet.
define internal %Slot @t2_stash(%Str %c) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %has = icmp eq i8 %st, 5
  br i1 %has, label %ok, label %make
make:
  %n = call %Slot @t2_hnew()
  call void @t2_hset(%Slot %t, %Str %c, %Slot %n)
  ret %Slot %n
ok:
  ret %Slot %s
}
; t2_mop_isa_arr(class) -> class\'s @ISA, the array lookup walks; made empty
; (and stored) when the class has none yet.
define internal %Array* @t2_mop_isa_arr(%Str %c) {
entry:
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %ok, label %make
ok:
  %iv = extractvalue %Slot %isa, 1
  %a = inttoptr i64 %iv to %Array*
  ret %Array* %a
make:
  %n = call %Array* @t2_new_array()
  call void @t2_mop_isa_set(%Str %c, %Array* %n)
  ret %Array* %n
}
define internal void @t2_mop_isa_set(%Str %c, %Array* %a) {
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_isa_key()
  %ai = ptrtoint %Array* %a to i64
  %as = call %Slot @t2_slot(i8 6, i64 %ai)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %as)
  ret void
}
define internal void @t2_mop_class(%Str %c) {
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hnew()
  call void @t2_hset(%Slot %t, %Str %c, %Slot %s)
  ret void
}
define internal %Str @t2_isa_key() {
  %k = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_isa, i64 0, i64 0), i64 4)
  ret %Str %k
}
; t2_mop_isa(class, parent): push parent onto class\'s @ISA.
define internal void @t2_mop_isa(%Str %c, %Str %p) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %tag = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %tag, 6
  br i1 %has, label %push, label %make
make:
  %na = call %Array* @t2_new_array()
  %ni = ptrtoint %Array* %na to i64
  %ns = call %Slot @t2_slot(i8 6, i64 %ni)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %ns)
  br label %push
push:
  %cur = phi %Slot [ %isa, %entry ], [ %ns, %make ]
  %cv = extractvalue %Slot %cur, 1
  %arr = inttoptr i64 %cv to %Array*
  %ps = call %Slot @t2_box_str(%Str %p)
  call void @t2_apush(%Array* %arr, %Slot %ps)
  ret void
}
define internal void @t2_mop_def(%Str %c, %Str %m, i8* %f) {
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %fi = ptrtoint i8* %f to i64
  %fs = call %Slot @t2_slot(i8 7, i64 %fi)
  call void @t2_hset(%Slot %s, %Str %m, %Slot %fs)
  ret void
}
; t2_sub_find(package, name, " at FILE line N.\n") -> the code the package\'s
; stash holds under name -- a sub stored into the glob at run time (no @ISA:
; a call by name is no method call) -- or perl\'s die, "Undefined subroutine
; &package::name called at ...", unwinding (t2_nomethod is called instead).
@lit_undefsub = private unnamed_addr constant [23 x i8] c"Undefined subroutine &\00"
@lit_called = private unnamed_addr constant [8 x i8] c" called\00"
define internal i8* @t2_sub_find(%Str %p, %Str %n, %Str %at) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %p)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %look, label %none
look:
  %f = call %Slot @t2_hget(%Slot %s, %Str %n)
  %ft = extractvalue %Slot %f, 0
  %code = icmp eq i8 %ft, 7
  br i1 %code, label %found, label %none
found:
  %fv = extractvalue %Slot %f, 1
  %fp = inttoptr i64 %fv to i8*
  ret i8* %fp
none:
  %u0 = call %Str @t2_str(i8* getelementptr ([23 x i8], [23 x i8]* @lit_undefsub, i64 0, i64 0), i64 22)
  %u1 = call %Str @t2_concat(%Str %u0, %Str %p)
  %c2 = call %Str @t2_str(i8* getelementptr ([3 x i8], [3 x i8]* @lit_colons, i64 0, i64 0), i64 2)
  %u2 = call %Str @t2_concat(%Str %u1, %Str %c2)
  %u3 = call %Str @t2_concat(%Str %u2, %Str %n)
  %c4 = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_called, i64 0, i64 0), i64 7)
  %u4 = call %Str @t2_concat(%Str %u3, %Str %c4)
  %full = call %Str @t2_concat(%Str %u4, %Str %at)
  call void @t2_die_unwind(%Str %full)
  ret i8* bitcast (%Slot (%Array*)* @t2_nomethod to i8*)
}
; t2_mfind1(class, m, skip) -> m\'s code in class (unless skip) or, depth first,
; its @ISA; null.
define internal i8* @t2_mfind1(%Str %c, %Str %m, i1 %skip) {
entry:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %own, label %none
own:
  br i1 %skip, label %parents, label %look
look:
  %f = call %Slot @t2_hget(%Slot %s, %Str %m)
  %ft = extractvalue %Slot %f, 0
  %code = icmp eq i8 %ft, 7
  br i1 %code, label %found, label %parents
found:
  %fv = extractvalue %Slot %f, 1
  %fp = inttoptr i64 %fv to i8*
  ret i8* %fp
parents:
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %walk, label %none
walk:
  %iv = extractvalue %Slot %isa, 1
  %arr = inttoptr i64 %iv to %Array*
  %n = call i64 @t2_alen(%Array* %arr)
  br label %loop
loop:
  %i = phi i64 [ 0, %walk ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %ps = call %Slot @t2_aget(%Array* %arr, i64 %i)
  %pn = call %Str @t2_slot_str(%Slot %ps)
  %r = call i8* @t2_mfind1(%Str %pn, %Str %m, i1 0)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ret, label %next
ret:
  ret i8* %r
next:
  %i2 = add i64 %i, 1
  br label %loop
none:
  ret i8* null
}
; UNIVERSAL: perl\'s stash at the root of every method lookup, holding isa,
; can, DOES and VERSION. t2_universal_setup makes it.
@lit_universal = private unnamed_addr constant [10 x i8] c"UNIVERSAL\00"
@lit_u_isa = private unnamed_addr constant [4 x i8] c"isa\00"
@lit_u_can = private unnamed_addr constant [4 x i8] c"can\00"
@lit_u_does = private unnamed_addr constant [5 x i8] c"DOES\00"
define internal %Str @t2_universal_key() {
  %k = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_universal, i64 0, i64 0), i64 9)
  ret %Str %k
}
define internal void @t2_universal_setup() {
  %u = call %Str @t2_universal_key()
  call void @t2_mop_class(%Str %u)
  %i = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_u_isa, i64 0, i64 0), i64 3)
  call void @t2_mop_def(%Str %u, %Str %i, i8* bitcast (%Slot (%Array*)* @t2_u_isa_w to i8*))
  %c = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_u_can, i64 0, i64 0), i64 3)
  call void @t2_mop_def(%Str %u, %Str %c, i8* bitcast (%Slot (%Array*)* @t2_u_can_w to i8*))
  %d = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_u_does, i64 0, i64 0), i64 4)
  call void @t2_mop_def(%Str %u, %Str %d, i8* bitcast (%Slot (%Array*)* @t2_u_isa_w to i8*))
  %v = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_vname, i64 0, i64 0), i64 7)
  call void @t2_mop_def(%Str %u, %Str %v, i8* bitcast (%Slot (%Array*)* @t2_u_version_w to i8*))
  ret void
}
; t2_mfind_u(class, m, skip) -> as t2_mfind1, and failing that UNIVERSAL\'s.
define internal i8* @t2_mfind_u(%Str %c, %Str %m, i1 %skip) {
entry:
  %r = call i8* @t2_mfind1(%Str %c, %Str %m, i1 %skip)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ok, label %root
ok:
  ret i8* %r
root:
  %u = call %Str @t2_universal_key()
  %ru = call i8* @t2_mfind1(%Str %u, %Str %m, i1 0)
  ret i8* %ru
}
; t2_inv_class(inv) -> an object\'s class, or a class name (t2_mresolve checked it).
define internal %Str @t2_inv_class(%Slot %inv) {
entry:
  %t = extractvalue %Slot %inv, 0
  %ish = icmp eq i8 %t, 5
  %isa = icmp eq i8 %t, 6
  %isref = or i1 %ish, %isa
  br i1 %isref, label %ref, label %name
ref:
  %cl = call %Slot @t2_class_of(%Slot %inv)
  %cn = call %Str @t2_slot_str(%Slot %cl)
  ret %Str %cn
name:
  %nn = call %Str @t2_slot_str(%Slot %inv)
  ret %Str %nn
}
; t2_isa_walk(class, target) -> class is target or, depth first, inherits it.
define internal i1 @t2_isa_walk(%Str %c, %Str %target) {
entry:
  %d = call i64 @t2_strcmp(%Str %c, %Str %target)
  %same = icmp eq i64 %d, 0
  br i1 %same, label %yes, label %stash
stash:
  %t = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %t, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %parents, label %no
parents:
  %k = call %Str @t2_isa_key()
  %isa = call %Slot @t2_hget(%Slot %s, %Str %k)
  %it = extractvalue %Slot %isa, 0
  %has = icmp eq i8 %it, 6
  br i1 %has, label %walk, label %no
walk:
  %iv = extractvalue %Slot %isa, 1
  %arr = inttoptr i64 %iv to %Array*
  %n = call i64 @t2_alen(%Array* %arr)
  br label %loop
loop:
  %i = phi i64 [ 0, %walk ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %no
body:
  %ps = call %Slot @t2_aget(%Array* %arr, i64 %i)
  %pn = call %Str @t2_slot_str(%Slot %ps)
  %r = call i1 @t2_isa_walk(%Str %pn, %Str %target)
  br i1 %r, label %yes, label %next
next:
  %i2 = add i64 %i, 1
  br label %loop
yes:
  ret i1 1
no:
  ret i1 0
}
; t2_bool(b) -> perl\'s true (1) or false (the empty string).
define internal %Slot @t2_bool(i1 %b) {
entry:
  br i1 %b, label %t, label %f
t:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
f:
  %e = call %Str @t2_str(i8* null, i64 0)
  %no = call %Slot @t2_box_str(%Str %e)
  ret %Slot %no
}
; UNIVERSAL::isa (and DOES): method isa ($other) { $self isa $other }
define internal %Slot @t2_u_isa_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %o = call %Slot @t2_aget(%Array* %args, i64 1)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %os = call %Str @t2_slot_str(%Slot %o)
  %b = call i1 @t2_isa_walk(%Str %c, %Str %os)
  %r = call %Slot @t2_bool(i1 %b)
  %rn = call %Slot @t2_list_of(%Slot %r, i1 %w)
  ret %Slot %rn
}
; t2_qr_match(re, subject) -> what a qr value\'s matcher gives: [start, end,
; groups...] or undef. A value of no class Regexp is a pattern built at run
; time: there is no graph of it -- stopped.
@lit_regexp = private unnamed_addr constant [7 x i8] c"Regexp\00"
@lit_matcher = private unnamed_addr constant [8 x i8] c"matcher\00"
@lit_qrpat = private unnamed_addr constant [8 x i8] c"pattern\00"
@msg_qr_runtime = private unnamed_addr constant [63 x i8] c"chalk: refused at run time: a regex pattern built at run time\0A\00"
define internal %Slot @t2_qr_match(%Slot %re, %Slot %subj) {
entry:
  %c = call %Slot @t2_class_of(%Slot %re)
  %cs = call %Str @t2_slot_str(%Slot %c)
  %rx = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_regexp, i64 0, i64 0), i64 6)
  %cmp = call i64 @t2_strcmp(%Str %cs, %Str %rx)
  %is = icmp eq i64 %cmp, 0
  br i1 %is, label %call, label %stop
stop:
  call void @t2_stop(i8* getelementptr ([63 x i8], [63 x i8]* @msg_qr_runtime, i64 0, i64 0), i64 62)
  unreachable
call:
  %mk = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_matcher, i64 0, i64 0), i64 7)
  %code = call %Slot @t2_hget(%Slot %re, %Str %mk)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %subj)
  store i1 0, i1* @t2_want
  %e = call %Slot** @t2_code_env(%Slot %code)
  %p = call i8* @t2_code_fn(%Slot %code)
  %f = bitcast i8* %p to %Slot (%Array*, %Slot**)*
  %r = call %Slot %f(%Array* %args, %Slot** %e)
  ret %Slot %r
}
; t2_pos_update(r, pos, z, keep): after an m//g -- matched ([start, end, ..]):
; pos is end, z end where the match was empty (else none); failed: both reset,
; unless /c (keep).
define internal void @t2_pos_update(%Slot %r, %Slot* %pc, %Slot* %zc, i1 %keep) {
entry:
  %t = extractvalue %Slot %r, 0
  %ok = icmp ne i8 %t, 0
  br i1 %ok, label %hit, label %miss
hit:
  %a = call %Array* @t2_aderef(%Slot %r)
  %s = call %Slot @t2_aget(%Array* %a, i64 0)
  %e = call %Slot @t2_aget(%Array* %a, i64 1)
  store %Slot %e, %Slot* %pc
  %si = extractvalue %Slot %s, 1
  %ei = extractvalue %Slot %e, 1
  %emp = icmp eq i64 %si, %ei
  %zz = select i1 %emp, %Slot %e, %Slot zeroinitializer
  store %Slot %zz, %Slot* %zc
  ret void
miss:
  br i1 %keep, label %done, label %reset
reset:
  store %Slot zeroinitializer, %Slot* %pc
  store %Slot zeroinitializer, %Slot* %zc
  br label %done
done:
  ret void
}
; t2_stash_tramp(args, env): a stash method called as a code value -- its
; code rides in env.
define internal %Slot @t2_stash_tramp(%Array* %args, %Slot** %env) {
entry:
  %f = bitcast %Slot** %env to %Slot (%Array*)*
  %r = call %Slot %f(%Array* %args)
  ret %Slot %r
}
; t2_unloaded_w: an unloaded sub\'s stash entry (can() finds it by name). Never
; called: a program that may call what can() hands back is refused.
define internal %Slot @t2_unloaded_w(%Array* %args) {
entry:
  unreachable
}
; UNIVERSAL::can: the method as a code value, or undef. (A list context gets a
; list, as a sub\'s wrapper gives: "[", A->can("x"), "]" read past its end.)
define internal %Slot @t2_u_can_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %m = call %Slot @t2_aget(%Array* %args, i64 1)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %ms = call %Str @t2_slot_str(%Slot %m)
  %fp = call i8* @t2_mfind_u(%Str %c, %Str %ms, i1 0)
  %none = icmp eq i8* %fp, null
  br i1 %none, label %undef, label %code
undef:
  %un = call %Slot @t2_list_of(%Slot zeroinitializer, i1 %w)
  ret %Slot %un
code:
  %e = bitcast i8* %fp to %Slot**
  %cv = call %Slot @t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* @t2_stash_tramp to i8*), %Slot** %e)
  %cn = call %Slot @t2_list_of(%Slot %cv, i1 %w)
  ret %Slot %cn
}
@lit_vkey = private unnamed_addr constant [9 x i8] c"$VERSION\00"
@lit_vname = private unnamed_addr constant [8 x i8] c"VERSION\00"
@lit_vver = private unnamed_addr constant [10 x i8] c" version \00"
@lit_vreq = private unnamed_addr constant [33 x i8] c" required--this is only version \00"
@lit_vnodef = private unnamed_addr constant [19 x i8] c" does not define $\00"
@lit_vnodef2 = private unnamed_addr constant [32 x i8] c"::VERSION--version check failed\00"
@lit_vneither = private unnamed_addr constant [59 x i8] c" defines neither package nor VERSION--version check failed\00"
; the call site t2_mresolve last saw (" at FILE line N.\n"): a UNIVERSAL method\'s die names it
@t2_call_at = internal global %Str zeroinitializer
; t2_mop_var(class, global): class\'s $VERSION is that global (VERSION reads it by the class\'s name).
define internal void @t2_mop_var(%Str %c, %Slot* %g) {
  %s = call %Slot @t2_stash(%Str %c)
  %k = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_vkey, i64 0, i64 0), i64 8)
  %gi = ptrtoint %Slot* %g to i64
  %gs = call %Slot @t2_slot(i8 1, i64 %gi)
  call void @t2_hset(%Slot %s, %Str %k, %Slot %gs)
  ret void
}
; t2_vnum(version) -> perl\'s number for it: decimal ("1.10" is 1.1), or dotted
; ("1.2.3", "v1.2": each part a thousandth of the one before).
define internal double @t2_vnum(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %some = icmp sgt i64 %n, 0
  br i1 %some, label %first, label %decimal
first:
  %c0 = load i8, i8* %p
  %isv = icmp eq i8 %c0, 118
  br i1 %isv, label %dotted, label %count
count:
  %ci = phi i64 [ 0, %first ], [ %ci2, %cstep ]
  %dots = phi i64 [ 0, %first ], [ %dots2, %cstep ]
  %cmore = icmp slt i64 %ci, %n
  br i1 %cmore, label %cstep, label %counted
cstep:
  %cp = getelementptr i8, i8* %p, i64 %ci
  %cc = load i8, i8* %cp
  %isdot = icmp eq i8 %cc, 46
  %inc = zext i1 %isdot to i64
  %dots2 = add i64 %dots, %inc
  %ci2 = add i64 %ci, 1
  br label %count
counted:
  %many = icmp sgt i64 %dots, 1
  br i1 %many, label %dotted, label %decimal
decimal:
  %sl = call %Slot @t2_box_str(%Str %s)
  %d = call double @t2_slot_num(%Slot %sl)
  ret double %d
dotted:
  %st0 = load i8, i8* %p
  %lead = icmp eq i8 %st0, 118
  %i0 = zext i1 %lead to i64
  br label %loop
loop:
  %i = phi i64 [ %i0, %dotted ], [ %inext, %digit ], [ %inext, %dot ]
  %part = phi i64 [ 0, %dotted ], [ %part2, %digit ], [ 0, %dot ]
  %acc = phi double [ 0.0, %dotted ], [ %acc, %digit ], [ %acc2, %dot ]
  %scale = phi double [ 1.0, %dotted ], [ %scale, %digit ], [ %scale2, %dot ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %ch, label %end
ch:
  %chp = getelementptr i8, i8* %p, i64 %i
  %chv = load i8, i8* %chp
  %inext = add i64 %i, 1
  %isd = icmp eq i8 %chv, 46
  br i1 %isd, label %dot, label %digit
dot:
  %pf = sitofp i64 %part to double
  %add = fmul double %pf, %scale
  %acc2 = fadd double %acc, %add
  %scale2 = fdiv double %scale, 1000.0
  br label %loop
digit:
  %dv = zext i8 %chv to i64
  %dd = sub i64 %dv, 48
  %p10 = mul i64 %part, 10
  %part2 = add i64 %p10, %dd
  br label %loop
end:
  %pf2 = sitofp i64 %part to double
  %add2 = fmul double %pf2, %scale
  %r = fadd double %acc, %add2
  ret double %r
}
; UNIVERSAL::VERSION: the class\'s own $VERSION; with a wanted version,
; perl\'s check, dying as perl does where it fails.
define internal %Slot @t2_u_version_w(%Array* %args) {
entry:
  %w = load i1, i1* @t2_want
  %inv = call %Slot @t2_aget(%Array* %args, i64 0)
  %c = call %Str @t2_inv_class(%Slot %inv)
  %tb = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %tb, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %look, label %check
look:
  %k = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_vkey, i64 0, i64 0), i64 8)
  %g = call %Slot @t2_hget(%Slot %s, %Str %k)
  %gt = extractvalue %Slot %g, 0
  %hasv = icmp eq i8 %gt, 1
  br i1 %hasv, label %load, label %check
load:
  %gi = extractvalue %Slot %g, 1
  %gp = inttoptr i64 %gi to %Slot*
  %vl = load %Slot, %Slot* %gp
  %vt = extractvalue %Slot %vl, 0
  %vdef = icmp ne i8 %vt, 0
  %vk = select i1 %vdef, i8 2, i8 1
  br label %check
check:
  %v = phi %Slot [ zeroinitializer, %entry ], [ zeroinitializer, %look ], [ %vl, %load ]
  %kind = phi i8 [ 0, %entry ], [ 1, %look ], [ %vk, %load ]
  %na = call i64 @t2_alen(%Array* %args)
  %req = icmp sgt i64 %na, 1
  br i1 %req, label %need, label %give
give:
  %rn = call %Slot @t2_list_of(%Slot %v, i1 %w)
  ret %Slot %rn
need:
  %want = call %Slot @t2_aget(%Array* %args, i64 1)
  %rs = call %Str @t2_slot_str(%Slot %want)
  switch i8 %kind, label %cmp [ i8 0, label %neither i8 1, label %nodef ]
cmp:
  %vs = call %Str @t2_slot_str(%Slot %v)
  %vn = call double @t2_vnum(%Str %vs)
  %wn = call double @t2_vnum(%Str %rs)
  %ok = fcmp oge double %vn, %wn
  br i1 %ok, label %give, label %low
low:
  %l0 = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_vver, i64 0, i64 0), i64 9)
  %l1 = call %Str @t2_concat(%Str %c, %Str %l0)
  %l2 = call %Str @t2_concat(%Str %l1, %Str %rs)
  %l3 = call %Str @t2_str(i8* getelementptr ([33 x i8], [33 x i8]* @lit_vreq, i64 0, i64 0), i64 32)
  %l4 = call %Str @t2_concat(%Str %l2, %Str %l3)
  %l5 = call %Str @t2_concat(%Str %l4, %Str %vs)
  br label %die
nodef:
  %n0 = call %Str @t2_str(i8* getelementptr ([19 x i8], [19 x i8]* @lit_vnodef, i64 0, i64 0), i64 18)
  %n1 = call %Str @t2_concat(%Str %c, %Str %n0)
  %n2 = call %Str @t2_concat(%Str %n1, %Str %c)
  %n3 = call %Str @t2_str(i8* getelementptr ([32 x i8], [32 x i8]* @lit_vnodef2, i64 0, i64 0), i64 31)
  %n4 = call %Str @t2_concat(%Str %n2, %Str %n3)
  br label %die
neither:
  %e0 = call %Str @t2_str(i8* getelementptr ([59 x i8], [59 x i8]* @lit_vneither, i64 0, i64 0), i64 58)
  %e1 = call %Str @t2_concat(%Str %c, %Str %e0)
  br label %die
die:
  %m = phi %Str [ %l5, %low ], [ %n4, %nodef ], [ %e1, %neither ]
  %at = load %Str, %Str* @t2_call_at
  %full = call %Str @t2_concat(%Str %m, %Str %at)
  call void @t2_die_unwind(%Str %full)
  ret %Slot zeroinitializer
}
@lit_tm_fetchsize = private unnamed_addr constant [10 x i8] c"FETCHSIZE\00"
@lit_tm_fetch = private unnamed_addr constant [6 x i8] c"FETCH\00"
@lit_tm_store = private unnamed_addr constant [6 x i8] c"STORE\00"
@lit_tm_push = private unnamed_addr constant [5 x i8] c"PUSH\00"
@lit_tm_pop = private unnamed_addr constant [4 x i8] c"POP\00"
@lit_tm_shift = private unnamed_addr constant [6 x i8] c"SHIFT\00"
@lit_tm_unshift = private unnamed_addr constant [8 x i8] c"UNSHIFT\00"
@lit_tm_exists = private unnamed_addr constant [7 x i8] c"EXISTS\00"
@lit_tm_delete = private unnamed_addr constant [7 x i8] c"DELETE\00"
@lit_tm_firstkey = private unnamed_addr constant [9 x i8] c"FIRSTKEY\00"
@lit_tm_nextkey = private unnamed_addr constant [8 x i8] c"NEXTKEY\00"
@lit_tm_clear = private unnamed_addr constant [6 x i8] c"CLEAR\00"
@lit_tm_tiearray = private unnamed_addr constant [9 x i8] c"TIEARRAY\00"
@lit_tm_tiehash = private unnamed_addr constant [8 x i8] c"TIEHASH\00"
@lit_tm_tiescalar = private unnamed_addr constant [10 x i8] c"TIESCALAR\00"
; THE CONTAINER PROTOCOL (perigrin: a tie swaps a container\'s metaobject).
; Every %Array -- an array, or a hash\'s pairs -- points at a metaobject:
; a vtable of its operations and a datum (a tie\'s object). The default\'s
; entries are the runtime\'s own functions (t2_aget_d, ...); t2_aget and the
; rest look the operation up there. A tie\'s entries call the object\'s
; methods; the other kind\'s entries stay the default\'s.
%Meta = type { i8**, %Slot }
@t2_vt_default = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hget_d to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hset_d to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hdelete_d to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hvalues_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hpairs_d to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_aexists_d to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_aset_len_d to i8*)
]
@t2_vt_tiearray = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_tie_aget to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_tie_aset to i8*),
  i8* bitcast (i64 (%Array*)* @t2_tie_alen to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_tie_apush to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_tie_apop to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_tie_ashift to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_tie_aunshift to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_tie_aappend to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_tie_aunshiftl to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hget_d to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hset_d to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hdelete_d to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hvalues_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hpairs_d to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_tie_aexists to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_tie_aset_len to i8*)
]
@t2_vt_tiehash = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hget to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_tie_hset to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_tie_hexists to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hdelete to i8*),
  i8* bitcast (i64 (%Slot)* @t2_tie_hcount to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hkeys to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hvalues to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hpairs to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_tie_hfroma to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_aexists_d to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_aset_len_d to i8*)
]
@t2_vt_mophash = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hget to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_tie_hset to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_tie_hexists to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_tie_hdelete to i8*),
  i8* bitcast (i64 (%Slot)* @t2_tie_hcount to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hkeys to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hvalues to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_tie_hpairs to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_tie_hfroma to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_aexists_d to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_aset_len_d to i8*)
]
@t2_meta_default = internal global %Meta { i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_default, i64 0, i64 0), %Slot zeroinitializer }
; @_ IS AN ARRAY OF ALIASES (perigrin): each element the call puts there is
; the caller\'s own -- a SCALAR REFERENCE (tag 9) to its variable, or to a
; fresh cell (a temporary, or what the callee pushes); an ELEMENT ALIAS (tag
; 10) of an array\'s or a hash\'s element, found where it is read or written,
; as perl\'s deferred element is; or a value as it is, READ-ONLY (a literal:
; perl dies on a store). Its metaobject reads through the alias and stores
; there; what moves an element (shift, pop, splice) moves the alias.
%Elv = type { i8, %Slot, %Slot }
@t2_vt_alias = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_alias_aget to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_alias_aset to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_alias_apush to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_alias_aunshift to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_alias_aunshiftl to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hget_d to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hset_d to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hdelete_d to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hvalues_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hpairs_d to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_aexists_d to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_aset_len_d to i8*)
]
@t2_meta_alias = internal global %Meta { i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_alias, i64 0, i64 0), %Slot zeroinitializer }
; A HASH OF CELLS (one an element reference was taken of, `\$h{k}`): each
; value boxed in a heap cell (t2_hcells), read and stored through it, as an
; array of aliases\' elements are. Its pairs are a plain %Array (the array
; entries the default\'s); its hash entries go through the cells. A delete
; takes the pair out (a reference keeps the cell); a store of a key not there
; makes a new cell; a whole assign truncates the pairs first (new cells).
@t2_vt_hcells = internal global [20 x i8*] [
  i8* bitcast (%Slot (%Array*, i64)* @t2_aget_d to i8*),
  i8* bitcast (void (%Array*, i64, %Slot, i8*, i64)* @t2_aset_d to i8*),
  i8* bitcast (i64 (%Array*)* @t2_alen_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_apush_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_apop_d to i8*),
  i8* bitcast (%Slot (%Array*)* @t2_ashift_d to i8*),
  i8* bitcast (void (%Array*, %Slot)* @t2_aunshift_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aappend_d to i8*),
  i8* bitcast (void (%Array*, %Array*)* @t2_aunshiftl_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hc_hget to i8*),
  i8* bitcast (void (%Slot, %Str, %Slot)* @t2_hc_hset to i8*),
  i8* bitcast (i1 (%Slot, %Str)* @t2_hexists_d to i8*),
  i8* bitcast (%Slot (%Slot, %Str)* @t2_hc_hdelete to i8*),
  i8* bitcast (i64 (%Slot)* @t2_hcount_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hkeys_d to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hc_hvalues to i8*),
  i8* bitcast (%Array* (%Slot)* @t2_hc_hpairs to i8*),
  i8* bitcast (void (%Slot, %Array*)* @t2_hfroma_d to i8*),
  i8* bitcast (i1 (%Array*, i64)* @t2_aexists_d to i8*),
  i8* bitcast (void (%Array*, i64)* @t2_aset_len_d to i8*)
]
@t2_meta_hcells = internal global %Meta { i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_hcells, i64 0, i64 0), %Slot zeroinitializer }
; t2_new_args() -> an empty @_, its elements aliases
define internal %Array* @t2_new_args() {
  %a = call %Array* @t2_new_array()
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_alias, %Meta** %mp
  ret %Array* %a
}
; t2_is_args(a) -> a is an @_ (its elements aliases)
define internal i1 @t2_is_args(%Array* %a) {
  %m = call %Meta* @t2_meta(%Array* %a)
  %y = icmp eq %Meta* %m, @t2_meta_alias
  ret i1 %y
}
; t2_elv(kind, container, key) -> an element alias: kind 0 an array\'s (the
; container\'s payload the %Array*, the key its index -- one from the end
; fixed now, as perl\'s is the element there at the call), 1 a hash\'s.
define internal %Slot @t2_elv(i8 %k, %Slot %c, %Slot %key) {
  %m = call i8* @malloc(i64 48)
  %e = bitcast i8* %m to %Elv*
  %kp = getelementptr %Elv, %Elv* %e, i32 0, i32 0
  store i8 %k, i8* %kp
  %cp = getelementptr %Elv, %Elv* %e, i32 0, i32 1
  store %Slot %c, %Slot* %cp
  %xp = getelementptr %Elv, %Elv* %e, i32 0, i32 2
  store %Slot %key, %Slot* %xp
  %i = ptrtoint i8* %m to i64
  %s = call %Slot @t2_slot(i8 10, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_elv_a(%Array* %a, i64 %i) {
  %n = call i64 @t2_alen(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fe = add i64 %i, %n
  %j = select i1 %neg, i64 %fe, i64 %i
  %ai = ptrtoint %Array* %a to i64
  %c = call %Slot @t2_slot(i8 1, i64 %ai)
  %x = call %Slot @t2_slot(i8 1, i64 %j)
  %s = call %Slot @t2_elv(i8 0, %Slot %c, %Slot %x)
  ret %Slot %s
}
define internal %Slot @t2_elv_h(%Slot %h, %Str %k) {
  %x = call %Slot @t2_box_str(%Str %k)
  %s = call %Slot @t2_elv(i8 1, %Slot %h, %Slot %x)
  ret %Slot %s
}
; t2_alias_val(raw) -> the value an element of @_ stands for now
define internal %Slot @t2_alias_val(%Slot %r) {
entry:
  %t = extractvalue %Slot %r, 0
  %p = extractvalue %Slot %r, 1
  switch i8 %t, label %own [ i8 9, label %cell
                             i8 10, label %elv ]
cell:
  %c = inttoptr i64 %p to %Slot*
  %v = load %Slot, %Slot* %c
  ret %Slot %v
elv:
  %e = inttoptr i64 %p to %Elv*
  %kp = getelementptr %Elv, %Elv* %e, i32 0, i32 0
  %k = load i8, i8* %kp
  %cp = getelementptr %Elv, %Elv* %e, i32 0, i32 1
  %cs = load %Slot, %Slot* %cp
  %xp = getelementptr %Elv, %Elv* %e, i32 0, i32 2
  %xs = load %Slot, %Slot* %xp
  %ish = icmp eq i8 %k, 1
  br i1 %ish, label %hash, label %arr
arr:
  %ai = extractvalue %Slot %cs, 1
  %a = inttoptr i64 %ai to %Array*
  %i = extractvalue %Slot %xs, 1
  %av = call %Slot @t2_aget(%Array* %a, i64 %i)
  ret %Slot %av
hash:
  %ks = call %Str @t2_slot_str(%Slot %xs)
  %hv = call %Slot @t2_hget(%Slot %cs, %Str %ks)
  ret %Slot %hv
own:
  ret %Slot %r
}
@lit_ro = private unnamed_addr constant [44 x i8] c"Modification of a read-only value attempted\00"
; t2_alias_store(raw, v, at) -> stored where the alias points (true); false
; where raw is no alias -- an absent element (made a fresh cell by the
; caller); perl\'s die on a read-only value.
define internal i1 @t2_alias_store(%Slot %r, %Slot %v, i8* %at, i64 %atn) {
entry:
  %t = extractvalue %Slot %r, 0
  %p = extractvalue %Slot %r, 1
  switch i8 %t, label %ro [ i8 9, label %cell
                            i8 10, label %elv
                            i8 0, label %undef ]
cell:
  %c = inttoptr i64 %p to %Slot*
  %isro = call i1 @t2_is_ro(%Slot* %c)
  br i1 %isro, label %ro, label %cellst
cellst:
  store %Slot %v, %Slot* %c
  ret i1 1
elv:
  %e = inttoptr i64 %p to %Elv*
  %kp = getelementptr %Elv, %Elv* %e, i32 0, i32 0
  %k = load i8, i8* %kp
  %cp = getelementptr %Elv, %Elv* %e, i32 0, i32 1
  %cs = load %Slot, %Slot* %cp
  %xp = getelementptr %Elv, %Elv* %e, i32 0, i32 2
  %xs = load %Slot, %Slot* %xp
  %ish = icmp eq i8 %k, 1
  br i1 %ish, label %hash, label %arr
arr:
  %ai = extractvalue %Slot %cs, 1
  %a = inttoptr i64 %ai to %Array*
  %i = extractvalue %Slot %xs, 1
  call void @t2_aset(%Array* %a, i64 %i, %Slot %v, i8* %at, i64 %atn)
  ret i1 1
hash:
  %ks = call %Str @t2_slot_str(%Slot %xs)
  call void @t2_hset(%Slot %cs, %Str %ks, %Slot %v)
  ret i1 1
undef:
  %absent = icmp eq i64 %p, 1
  br i1 %absent, label %none, label %ro
none:
  ret i1 0
ro:
  %m0 = call %Str @t2_str(i8* getelementptr ([44 x i8], [44 x i8]* @lit_ro, i64 0, i64 0), i64 43)
  %as = call %Str @t2_str(i8* %at, i64 %atn)
  %m = call %Str @t2_concat(%Str %m0, %Str %as)
  call void @t2_die_unwind(%Str %m)
  ret i1 1
}
; t2_fresh(v) -> a scalar reference to a new cell holding v
define internal %Slot @t2_fresh(%Slot %v) {
  %c = call %Slot* @t2_cell_new()
  store %Slot %v, %Slot* %c
  %s = call %Slot @t2_sref(%Slot* %c)
  ret %Slot %s
}
define internal %Slot @t2_alias_aget(%Array* %a, i64 %i) {
  %r = call %Slot @t2_aget_d(%Array* %a, i64 %i)
  %v = call %Slot @t2_alias_val(%Slot %r)
  ret %Slot %v
}
define internal void @t2_alias_aset(%Array* %a, i64 %i, %Slot %v, i8* %at, i64 %atn) {
entry:
  %n = call i64 @t2_alen_d(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fe = add i64 %i, %n
  %j = select i1 %neg, i64 %fe, i64 %i
  %lo = icmp slt i64 %j, 0
  %hi = icmp sge i64 %j, %n
  %out = or i1 %lo, %hi
  br i1 %out, label %fresh, label %have
have:
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %r = load %Slot, %Slot* %p
  %done = call i1 @t2_alias_store(%Slot %r, %Slot %v, i8* %at, i64 %atn)
  br i1 %done, label %ok, label %fresh
fresh:
  %f = call %Slot @t2_fresh(%Slot %v)
  call void @t2_aset_d(%Array* %a, i64 %i, %Slot %f, i8* %at, i64 %atn)
  br label %ok
ok:
  ret void
}
define internal void @t2_alias_apush(%Array* %a, %Slot %v) {
  %f = call %Slot @t2_fresh(%Slot %v)
  call void @t2_apush_d(%Array* %a, %Slot %f)
  ret void
}
define internal void @t2_alias_aunshift(%Array* %a, %Slot %v) {
  %f = call %Slot @t2_fresh(%Slot %v)
  call void @t2_aunshift_d(%Array* %a, %Slot %f)
  ret void
}
define internal void @t2_alias_aunshiftl(%Array* %a, %Array* %l) {
entry:
  %n = call i64 @t2_alen(%Array* %l)
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %l, i64 %im)
  call void @t2_alias_aunshift(%Array* %a, %Slot %v)
  br label %loop
done:
  ret void
}
; t2_aslice_alias(a, ix) / t2_hslice_alias(h, keys) -> an @_ of an alias of
; each element a slice names, in its order
define internal %Array* @t2_aslice_alias(%Array* %a, %Array* %ix) {
entry:
  %n = call i64 @t2_alen(%Array* %ix)
  %r = call %Array* @t2_new_args()
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k2, %body ]
  %more = icmp slt i64 %k, %n
  br i1 %more, label %body, label %done
body:
  %is = call %Slot @t2_aget(%Array* %ix, i64 %k)
  %i = call i64 @t2_slot_i64(%Slot %is)
  %e = call %Slot @t2_elv_a(%Array* %a, i64 %i)
  call void @t2_apush_d(%Array* %r, %Slot %e)
  %k2 = add i64 %k, 1
  br label %loop
done:
  ret %Array* %r
}
define internal %Array* @t2_hslice_alias(%Slot %h, %Array* %ks) {
entry:
  %n = call i64 @t2_alen(%Array* %ks)
  %r = call %Array* @t2_new_args()
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k2, %body ]
  %more = icmp slt i64 %k, %n
  br i1 %more, label %body, label %done
body:
  %ksl = call %Slot @t2_aget(%Array* %ks, i64 %k)
  %key = call %Str @t2_slot_str(%Slot %ksl)
  %e = call %Slot @t2_elv_h(%Slot %h, %Str %key)
  call void @t2_apush_d(%Array* %r, %Slot %e)
  %k2 = add i64 %k, 1
  br label %loop
done:
  ret %Array* %r
}
; t2_apush_alias(args, raw): an alias (or a read-only value) put on @_ as it is
define internal void @t2_apush_alias(%Array* %a, %Slot %r) {
  call void @t2_apush_d(%Array* %a, %Slot %r)
  ret void
}
; t2_aappend_alias(args, s): each element of s aliased on @_ -- an @_\'s own
; aliases handed on as they are (`f(@_)`), another array\'s elements each
; an element alias.
define internal void @t2_aappend_alias(%Array* %d, %Array* %s) {
entry:
  %n = call i64 @t2_alen(%Array* %s)
  %own = call i1 @t2_is_args(%Array* %s)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  br i1 %own, label %raw, label %el
raw:
  %r = call %Slot @t2_aget_d(%Array* %s, i64 %i)
  call void @t2_apush_d(%Array* %d, %Slot %r)
  br label %next
el:
  %e = call %Slot @t2_elv_a(%Array* %s, i64 %i)
  call void @t2_apush_d(%Array* %d, %Slot %e)
  br label %next
next:
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret void
}
; ELEMENT REFERENCES (`\$a[i]`, `\(@a)`): perl\'s element is a scalar of its
; own, which a reference keeps past a grow, a shift, a refill. An array one is
; taken of becomes AN ARRAY OF ALIASES, as @_ is (its metaobject
; t2_meta_alias): each element boxed in a heap cell (t2_acells), read and
; stored through it; what moves an element (shift, unshift) moves its cell, a
; refill makes new ones. The reference is the cell\'s (tag 9), as `\$x` is.
@msg_eref_tied = private unnamed_addr constant [71 x i8] c"chalk: refused at run time: a reference to an element of a tied array\0A\00"
@msg_eref_ro = private unnamed_addr constant [65 x i8] c"chalk: refused at run time: a reference to a read-only argument\0A\00"
; t2_acells(a): a\'s elements each boxed in a cell (once; an @_ is already).
; A tied array\'s elements are its class\'s: stopped.
define internal void @t2_acells(%Array* %a) {
entry:
  %m = call %Meta* @t2_meta(%Array* %a)
  %al = icmp eq %Meta* %m, @t2_meta_alias
  br i1 %al, label %done, label %plain
plain:
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %box, label %tied
tied:
  call void @t2_stop(i8* getelementptr ([71 x i8], [71 x i8]* @msg_eref_tied, i64 0, i64 0), i64 70)
  unreachable
box:
  %n = call i64 @t2_alen_d(%Array* %a)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ 0, %box ], [ %i2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %mark
body:
  %p = getelementptr %Slot, %Slot* %els, i64 %i
  %v = load %Slot, %Slot* %p
  %t = extractvalue %Slot %v, 0
  %w = extractvalue %Slot %v, 1
  %ut = icmp eq i8 %t, 0
  %uw = icmp eq i64 %w, 1
  %absent = and i1 %ut, %uw   ; (a hole stays one: a reference to it makes it)
  br i1 %absent, label %next, label %wrap
wrap:
  %f = call %Slot @t2_fresh(%Slot %v)
  store %Slot %f, %Slot* %p
  br label %next
next:
  %i2 = add i64 %i, 1
  br label %loop
mark:
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_alias, %Meta** %mp
  br label %done
done:
  ret void
}
; t2_aelem_ref(a, i, at) -> a reference to a\'s element i (one from the end
; for i < 0; perl\'s die before the start, naming at -- an eval\'s to catch:
; undef comes back, dying; past the end the array grown to it). Of an @_,
; the caller\'s own: its variable\'s cell, its element\'s (an element alias
; resolved -- an array\'s, or a hash\'s: t2_helem_ref -- and kept so); a
; literal there is read-only (stopped: a store through it would die in perl).
define internal %Slot @t2_aelem_ref(%Array* %a, i64 %i, i8* %at, i64 %atn) {
entry:
  call void @t2_acells(%Array* %a)
  %n = call i64 @t2_alen_d(%Array* %a)
  %neg = icmp slt i64 %i, 0
  %fe = add i64 %i, %n
  %j = select i1 %neg, i64 %fe, i64 %i
  %lo = icmp slt i64 %j, 0
  br i1 %lo, label %die, label %grow
die:
  %dm = call %Str @t2_str(i8* getelementptr ([64 x i8], [64 x i8]* @lit_aset, i64 0, i64 0), i64 63)
  %ds = call %Str @t2_i64_str(i64 %i)
  %dm2 = call %Str @t2_concat(%Str %dm, %Str %ds)
  %da = call %Str @t2_str(i8* %at, i64 %atn)
  %dm3 = call %Str @t2_concat(%Str %dm2, %Str %da)
  call void @t2_die_unwind(%Str %dm3)
  ret %Slot zeroinitializer
grow:
  %j1 = add i64 %j, 1
  call void @t2_agrow(%Array* %a, i64 %j1)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  %r = load %Slot, %Slot* %p
  %t = extractvalue %Slot %r, 0
  %w = extractvalue %Slot %r, 1
  switch i8 %t, label %ro [ i8 9, label %cell
                            i8 10, label %elv
                            i8 0, label %undef ]
cell:
  ret %Slot %r
undef:
  %absent = icmp eq i64 %w, 1
  br i1 %absent, label %fresh, label %ro
fresh:
  %f = call %Slot @t2_fresh(%Slot zeroinitializer)
  store %Slot %f, %Slot* %p
  ret %Slot %f
elv:
  %e = inttoptr i64 %w to %Elv*
  %kp = getelementptr %Elv, %Elv* %e, i32 0, i32 0
  %k = load i8, i8* %kp
  %cp = getelementptr %Elv, %Elv* %e, i32 0, i32 1
  %cs = load %Slot, %Slot* %cp
  %xp = getelementptr %Elv, %Elv* %e, i32 0, i32 2
  %xs = load %Slot, %Slot* %xp
  %ish = icmp eq i8 %k, 1
  br i1 %ish, label %hash, label %arr
arr:
  %ai = extractvalue %Slot %cs, 1
  %inner = inttoptr i64 %ai to %Array*
  %ix = extractvalue %Slot %xs, 1
  %ir = call %Slot @t2_aelem_ref(%Array* %inner, i64 %ix, i8* %at, i64 %atn)
  %dying = load i1, i1* @t2_dying
  br i1 %dying, label %died, label %keep
died:
  ret %Slot %ir
keep:
  %ep2 = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els2 = load %Slot*, %Slot** %ep2
  %p2 = getelementptr %Slot, %Slot* %els2, i64 %j
  store %Slot %ir, %Slot* %p2
  ret %Slot %ir
hash:
  %hk = call %Str @t2_slot_str(%Slot %xs)
  %hr = call %Slot @t2_helem_ref(%Slot %cs, %Str %hk)
  %ep3 = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els3 = load %Slot*, %Slot** %ep3
  %p3 = getelementptr %Slot, %Slot* %els3, i64 %j
  store %Slot %hr, %Slot* %p3
  ret %Slot %hr
ro:
  call void @t2_stop(i8* getelementptr ([65 x i8], [65 x i8]* @msg_eref_ro, i64 0, i64 0), i64 64)
  unreachable
}
; t2_alias_of(r) -> what @_ holds for a read through an element reference r:
; the reference itself, the element\'s cell. One of no element (a foreach
; alias\'s guard over a hole is undef) is stopped: perl\'s would make it.
@msg_alias_none = private unnamed_addr constant [68 x i8] c"chalk: refused at run time: an alias of an array element not there\0A\00"
define internal %Slot @t2_alias_of(%Slot %r) {
entry:
  %t = extractvalue %Slot %r, 0
  %c = icmp eq i8 %t, 9
  br i1 %c, label %ok, label %none
ok:
  ret %Slot %r
none:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_alias_none, i64 0, i64 0), i64 67)
  unreachable
}
; t2_aelem_refs(a) -> `\(@a)`: a new list of a reference to each element
define internal %Array* @t2_aelem_refs(%Array* %a) {
entry:
  call void @t2_acells(%Array* %a)
  %n = call i64 @t2_alen_d(%Array* %a)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %e = call %Slot @t2_aelem_ref(%Array* %a, i64 %i, i8* null, i64 0)
  call void @t2_apush_d(%Array* %r, %Slot %e)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
; HASH ELEMENT REFERENCES (`\$h{k}`): the hash made one of cells
; (t2_meta_hcells), the reference the element\'s cell (tag 9), as `\$x` is.
@msg_href_tied = private unnamed_addr constant [70 x i8] c"chalk: refused at run time: a reference to an element of a tied hash\0A\00"
; t2_hcells(h): h\'s values each boxed in a cell (once). A tied hash\'s (or a
; MOP object\'s, %SIG\'s) elements are its class\'s: stopped.
define internal void @t2_hcells(%Slot %h) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %m = call %Meta* @t2_meta(%Array* %a)
  %hc = icmp eq %Meta* %m, @t2_meta_hcells
  br i1 %hc, label %done, label %plain
plain:
  %d = icmp eq %Meta* %m, @t2_meta_default
  br i1 %d, label %box, label %tied
tied:
  call void @t2_stop(i8* getelementptr ([70 x i8], [70 x i8]* @msg_href_tied, i64 0, i64 0), i64 69)
  unreachable
box:
  %n = call i64 @t2_alen_d(%Array* %a)
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ 2, %box ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %mark
body:
  %p = getelementptr %Slot, %Slot* %els, i64 %i
  %v = load %Slot, %Slot* %p
  %f = call %Slot @t2_fresh(%Slot %v)
  store %Slot %f, %Slot* %p
  %i2 = add i64 %i, 2
  br label %loop
mark:
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* @t2_meta_hcells, %Meta** %mp
  br label %done
done:
  ret void
}
; t2_helem_ref(h, k) -> a reference to h\'s element k: its cell, the key made
; (undef) where it is not there, as perl\'s `\$h{k}` makes it.
define internal %Slot @t2_helem_ref(%Slot %h, %Str %k) {
entry:
  call void @t2_hcells(%Slot %h)
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %add, label %have
add:
  %f = call %Slot @t2_fresh(%Slot zeroinitializer)
  %ks = call %Slot @t2_box_str(%Str %k)
  call void @t2_apush_d(%Array* %a, %Slot %ks)
  call void @t2_apush_d(%Array* %a, %Slot %f)
  ret %Slot %f
have:
  %j = add i64 %i, 1
  %r = call %Slot @t2_aget_d(%Array* %a, i64 %j)
  ret %Slot %r
}
; the hash entries of a hash of cells (t2_vt_hcells)
define internal %Slot @t2_hc_hget(%Slot %h, %Str %k) {
  %r = call %Slot @t2_hget_d(%Slot %h, %Str %k)
  %v = call %Slot @t2_alias_val(%Slot %r)
  ret %Slot %v
}
define internal void @t2_hc_hset(%Slot %h, %Str %k, %Slot %v) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %add, label %put
add:
  %f = call %Slot @t2_fresh(%Slot %v)
  %ks = call %Slot @t2_box_str(%Str %k)
  call void @t2_apush_d(%Array* %a, %Slot %ks)
  call void @t2_apush_d(%Array* %a, %Slot %f)
  ret void
put:
  %j = add i64 %i, 1
  %r = call %Slot @t2_aget_d(%Array* %a, i64 %j)
  %rp = extractvalue %Slot %r, 1
  %c = inttoptr i64 %rp to %Slot*
  store %Slot %v, %Slot* %c
  ret void
}
define internal %Slot @t2_hc_hdelete(%Slot %h, %Str %k) {
  %r = call %Slot @t2_hdelete_d(%Slot %h, %Str %k)
  %v = call %Slot @t2_alias_val(%Slot %r)
  ret %Slot %v
}
; t2_hc_vals(l): each cell of l (from index 0 on, every other one from start) read
define internal void @t2_hc_read(%Array* %l, i64 %from, i64 %step) {
entry:
  %n = call i64 @t2_alen_d(%Array* %l)
  %ep = getelementptr %Array, %Array* %l, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %i = phi i64 [ %from, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %p = getelementptr %Slot, %Slot* %els, i64 %i
  %r = load %Slot, %Slot* %p
  %v = call %Slot @t2_alias_val(%Slot %r)
  store %Slot %v, %Slot* %p
  %i2 = add i64 %i, %step
  br label %loop
done:
  ret void
}
define internal %Array* @t2_hc_hvalues(%Slot %h) {
  %r = call %Array* @t2_hvalues_d(%Slot %h)
  call void @t2_hc_read(%Array* %r, i64 0, i64 1)
  ret %Array* %r
}
define internal %Array* @t2_hc_hpairs(%Slot %h) {
  %r = call %Array* @t2_hpairs_d(%Slot %h)
  call void @t2_hc_read(%Array* %r, i64 1, i64 2)
  ret %Array* %r
}
; t2_meta(a) -> the metaobject a container points at
define internal %Meta* @t2_meta(%Array* %a) {
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  %m = load %Meta*, %Meta** %mp
  ret %Meta* %m
}
define internal i8* @t2_vt(%Array* %a, i64 %k) {
  %m = call %Meta* @t2_meta(%Array* %a)
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  %vt = load i8**, i8*** %vp
  %fp = getelementptr i8*, i8** %vt, i64 %k
  %f = load i8*, i8** %fp
  ret i8* %f
}
define internal %Slot @t2_aget(%Array* %p0, i64 %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 0)
  %fn = bitcast i8* %f to %Slot (%Array*, i64)*
  %r = call %Slot %fn(%Array* %p0, i64 %p1)
  ret %Slot %r
}
define internal void @t2_aset(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 1)
  %fn = bitcast i8* %f to void (%Array*, i64, %Slot, i8*, i64)*
  call void %fn(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4)
  ret void
}
define internal i64 @t2_alen(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 2)
  %fn = bitcast i8* %f to i64 (%Array*)*
  %r = call i64 %fn(%Array* %p0)
  ret i64 %r
}
define internal void @t2_apush(%Array* %p0, %Slot %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 3)
  %fn = bitcast i8* %f to void (%Array*, %Slot)*
  call void %fn(%Array* %p0, %Slot %p1)
  ret void
}
define internal %Slot @t2_apop(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 4)
  %fn = bitcast i8* %f to %Slot (%Array*)*
  %r = call %Slot %fn(%Array* %p0)
  ret %Slot %r
}
define internal %Slot @t2_ashift(%Array* %p0) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 5)
  %fn = bitcast i8* %f to %Slot (%Array*)*
  %r = call %Slot %fn(%Array* %p0)
  ret %Slot %r
}
define internal void @t2_aunshift(%Array* %p0, %Slot %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 6)
  %fn = bitcast i8* %f to void (%Array*, %Slot)*
  call void %fn(%Array* %p0, %Slot %p1)
  ret void
}
define internal void @t2_aappend(%Array* %p0, %Array* %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 7)
  %fn = bitcast i8* %f to void (%Array*, %Array*)*
  call void %fn(%Array* %p0, %Array* %p1)
  ret void
}
define internal void @t2_aunshiftl(%Array* %p0, %Array* %p1) {
  %a = bitcast %Array* %p0 to %Array*
  %f = call i8* @t2_vt(%Array* %a, i64 8)
  %fn = bitcast i8* %f to void (%Array*, %Array*)*
  call void %fn(%Array* %p0, %Array* %p1)
  ret void
}
; (a read through undef is undef, as perl\'s -- which makes the hash; a write
; through one B::SoN spells as the hash made first)
define internal %Slot @t2_hget(%Slot %p0, %Str %p1) {
entry:
  %t = extractvalue %Slot %p0, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  ret %Slot zeroinitializer
go:
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 9)
  %fn = bitcast i8* %f to %Slot (%Slot, %Str)*
  %r = call %Slot %fn(%Slot %p0, %Str %p1)
  ret %Slot %r
}
define internal void @t2_hset(%Slot %p0, %Str %p1, %Slot %p2) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 10)
  %fn = bitcast i8* %f to void (%Slot, %Str, %Slot)*
  call void %fn(%Slot %p0, %Str %p1, %Slot %p2)
  ret void
}
define internal i1 @t2_hexists(%Slot %p0, %Str %p1) {
entry:
  %t = extractvalue %Slot %p0, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %undef, label %go
undef:
  ret i1 0
go:
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 11)
  %fn = bitcast i8* %f to i1 (%Slot, %Str)*
  %r = call i1 %fn(%Slot %p0, %Str %p1)
  ret i1 %r
}
define internal %Slot @t2_hdelete(%Slot %p0, %Str %p1) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 12)
  %fn = bitcast i8* %f to %Slot (%Slot, %Str)*
  %r = call %Slot %fn(%Slot %p0, %Str %p1)
  ret %Slot %r
}
define internal i64 @t2_hcount(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 13)
  %fn = bitcast i8* %f to i64 (%Slot)*
  %r = call i64 %fn(%Slot %p0)
  ret i64 %r
}
define internal %Array* @t2_hkeys(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 14)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal %Array* @t2_hvalues(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 15)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal %Array* @t2_hpairs(%Slot %p0) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 16)
  %fn = bitcast i8* %f to %Array* (%Slot)*
  %r = call %Array* %fn(%Slot %p0)
  ret %Array* %r
}
define internal void @t2_hfroma(%Slot %p0, %Array* %p1) {
  %a = call %Array* @t2_harr(%Slot %p0)
  %f = call i8* @t2_vt(%Array* %a, i64 17)
  %fn = bitcast i8* %f to void (%Slot, %Array*)*
  call void %fn(%Slot %p0, %Array* %p1)
  ret void
}
; t2_tie_obj(a) -> the object a tied container\'s metaobject holds
define internal %Slot @t2_tie_obj(%Array* %a) {
  %m = call %Meta* @t2_meta(%Array* %a)
  %dp = getelementptr %Meta, %Meta* %m, i32 0, i32 1
  %d = load %Slot, %Slot* %dp
  ret %Slot %d
}
; t2_tie_call(args, name) -> the method name of args[0] called with args, in scalar context
define internal %Slot @t2_tie_call(%Array* %args, %Str %m) {
  %o = call %Slot @t2_aget(%Array* %args, i64 0)
  %e = call %Str @t2_str(i8* null, i64 0)
  %fp = call i8* @t2_mresolve(%Slot %o, %Str %m, %Str %e, %Str %e, i8 0)
  %w = load i1, i1* @t2_want
  store i1 0, i1* @t2_want
  %f = bitcast i8* %fp to %Slot (%Array*)*
  %r = call %Slot %f(%Array* %args)
  store i1 %w, i1* @t2_want
  ret %Slot %r
}
define internal i64 @t2_tie_alen(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t0.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t0.args, %Slot %o)
  %t0.m = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_tm_fetchsize, i64 0, i64 0), i64 9)
  %t0 = call %Slot @t2_tie_call(%Array* %t0.args, %Str %t0.m)
  %n = call i64 @t2_slot_i64(%Slot %t0)
  ret i64 %n
}
define internal %Slot @t2_tie_aget(%Array* %p0, i64 %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %neg = icmp slt i64 %p1, 0
  br i1 %neg, label %fix, label %go
fix:
  %sz = call i64 @t2_tie_alen(%Array* %a)
  %j0 = add i64 %p1, %sz
  br label %go
go:
  %j = phi i64 [ %p1, %entry ], [ %j0, %fix ]
  %js = call %Slot @t2_box_i64(i64 %j)
  %t1.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t1.args, %Slot %o)
  call void @t2_apush(%Array* %t1.args, %Slot %js)
  %t1.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t1 = call %Slot @t2_tie_call(%Array* %t1.args, %Str %t1.m)
  ret %Slot %t1
}
define internal void @t2_tie_aset(%Array* %p0, i64 %p1, %Slot %p2, i8* %p3, i64 %p4) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %neg = icmp slt i64 %p1, 0
  br i1 %neg, label %fix, label %go
fix:
  %sz = call i64 @t2_tie_alen(%Array* %a)
  %j0 = add i64 %p1, %sz
  br label %go
go:
  %j = phi i64 [ %p1, %entry ], [ %j0, %fix ]
  %js = call %Slot @t2_box_i64(i64 %j)
  %t2.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t2.args, %Slot %o)
  call void @t2_apush(%Array* %t2.args, %Slot %js)
  call void @t2_apush(%Array* %t2.args, %Slot %p2)
  %t2.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t2 = call %Slot @t2_tie_call(%Array* %t2.args, %Str %t2.m)
  ret void
}
define internal void @t2_tie_apush(%Array* %p0, %Slot %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t3.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t3.args, %Slot %o)
  call void @t2_apush(%Array* %t3.args, %Slot %p1)
  %t3.m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_tm_push, i64 0, i64 0), i64 4)
  %t3 = call %Slot @t2_tie_call(%Array* %t3.args, %Str %t3.m)
  ret void
}
define internal %Slot @t2_tie_apop(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t4.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t4.args, %Slot %o)
  %t4.m = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_tm_pop, i64 0, i64 0), i64 3)
  %t4 = call %Slot @t2_tie_call(%Array* %t4.args, %Str %t4.m)
  ret %Slot %t4
}
define internal %Slot @t2_tie_ashift(%Array* %p0) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t5.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t5.args, %Slot %o)
  %t5.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_shift, i64 0, i64 0), i64 5)
  %t5 = call %Slot @t2_tie_call(%Array* %t5.args, %Str %t5.m)
  ret %Slot %t5
}
define internal void @t2_tie_aunshift(%Array* %p0, %Slot %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t6.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t6.args, %Slot %o)
  call void @t2_apush(%Array* %t6.args, %Slot %p1)
  %t6.m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_unshift, i64 0, i64 0), i64 7)
  %t6 = call %Slot @t2_tie_call(%Array* %t6.args, %Str %t6.m)
  ret void
}
define internal void @t2_tie_aappend(%Array* %p0, %Array* %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_aappend(%Array* %args, %Array* %p1)
  %m = call %Str @t2_str(i8* getelementptr ([5 x i8], [5 x i8]* @lit_tm_push, i64 0, i64 0), i64 4)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal void @t2_tie_aunshiftl(%Array* %p0, %Array* %p1) {
entry:
  %a = bitcast %Array* %p0 to %Array*
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %o)
  call void @t2_aappend(%Array* %args, %Array* %p1)
  %m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_unshift, i64 0, i64 0), i64 7)
  %r = call %Slot @t2_tie_call(%Array* %args, %Str %m)
  ret void
}
define internal %Slot @t2_tie_hget(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t7.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t7.args, %Slot %o)
  call void @t2_apush(%Array* %t7.args, %Slot %ks)
  %t7.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t7 = call %Slot @t2_tie_call(%Array* %t7.args, %Str %t7.m)
  ret %Slot %t7
}
define internal void @t2_tie_hset(%Slot %p0, %Str %p1, %Slot %p2) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t8.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t8.args, %Slot %o)
  call void @t2_apush(%Array* %t8.args, %Slot %ks)
  call void @t2_apush(%Array* %t8.args, %Slot %p2)
  %t8.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t8 = call %Slot @t2_tie_call(%Array* %t8.args, %Str %t8.m)
  ret void
}
define internal i1 @t2_tie_hexists(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t9.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t9.args, %Slot %o)
  call void @t2_apush(%Array* %t9.args, %Slot %ks)
  %t9.m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_exists, i64 0, i64 0), i64 6)
  %t9 = call %Slot @t2_tie_call(%Array* %t9.args, %Str %t9.m)
  %b = call i1 @t2_truth_slot(%Slot %t9)
  ret i1 %b
}
define internal %Slot @t2_tie_hdelete(%Slot %p0, %Str %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Slot @t2_box_str(%Str %p1)
  %t10.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t10.args, %Slot %o)
  call void @t2_apush(%Array* %t10.args, %Slot %ks)
  %t10.m = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_delete, i64 0, i64 0), i64 6)
  %t10 = call %Slot @t2_tie_call(%Array* %t10.args, %Str %t10.m)
  ret %Slot %t10
}
define internal %Array* @t2_tie_hkeys(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_new_array()
  %t11.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t11.args, %Slot %o)
  %t11.m = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_tm_firstkey, i64 0, i64 0), i64 8)
  %t11 = call %Slot @t2_tie_call(%Array* %t11.args, %Str %t11.m)
  br label %loop
loop:
  %k = phi %Slot [ %t11, %entry ], [ %t12, %more ]
  %kt = extractvalue %Slot %k, 0
  %done = icmp eq i8 %kt, 0
  br i1 %done, label %end, label %more
more:
  call void @t2_apush(%Array* %ks, %Slot %k)
  %t12.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t12.args, %Slot %o)
  call void @t2_apush(%Array* %t12.args, %Slot %k)
  %t12.m = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_nextkey, i64 0, i64 0), i64 7)
  %t12 = call %Slot @t2_tie_call(%Array* %t12.args, %Str %t12.m)
  br label %loop
end:
  ret %Array* %ks
}
define internal i64 @t2_tie_hcount(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  ret i64 %n
}
define internal %Array* @t2_tie_hvalues(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  %out = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %ks, i64 %i)
  %t13.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t13.args, %Slot %o)
  call void @t2_apush(%Array* %t13.args, %Slot %k)
  %t13.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t13 = call %Slot @t2_tie_call(%Array* %t13.args, %Str %t13.m)
  call void @t2_apush(%Array* %out, %Slot %t13)
  %i2 = add i64 %i, 1
  br label %loop
end:
  ret %Array* %out
}
define internal %Array* @t2_tie_hpairs(%Slot %p0) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ks = call %Array* @t2_tie_hkeys(%Slot %p0)
  %n = call i64 @t2_alen(%Array* %ks)
  %out = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %ks, i64 %i)
  call void @t2_apush(%Array* %out, %Slot %k)
  %t14.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t14.args, %Slot %o)
  call void @t2_apush(%Array* %t14.args, %Slot %k)
  %t14.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_fetch, i64 0, i64 0), i64 5)
  %t14 = call %Slot @t2_tie_call(%Array* %t14.args, %Str %t14.m)
  call void @t2_apush(%Array* %out, %Slot %t14)
  %i2 = add i64 %i, 1
  br label %loop
end:
  ret %Array* %out
}
define internal void @t2_tie_hfroma(%Slot %p0, %Array* %p1) {
entry:
  %a = call %Array* @t2_harr(%Slot %p0)
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %t15.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t15.args, %Slot %o)
  %t15.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_clear, i64 0, i64 0), i64 5)
  %t15 = call %Slot @t2_tie_call(%Array* %t15.args, %Str %t15.m)
  %n = call i64 @t2_alen(%Array* %p1)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %go = icmp slt i64 %i, %n
  br i1 %go, label %body, label %end
body:
  %k = call %Slot @t2_aget(%Array* %p1, i64 %i)
  %i1 = add i64 %i, 1
  %val = call %Slot @t2_aget(%Array* %p1, i64 %i1)
  %t16.args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %t16.args, %Slot %o)
  call void @t2_apush(%Array* %t16.args, %Slot %k)
  call void @t2_apush(%Array* %t16.args, %Slot %val)
  %t16.m = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_store, i64 0, i64 0), i64 5)
  %t16 = call %Slot @t2_tie_call(%Array* %t16.args, %Str %t16.m)
  %i2 = add i64 %i, 2
  br label %loop
end:
  ret void
}
; t2_tie(a, vt, class, args, ctor) -> the object ctor (TIEARRAY/TIEHASH) made; a now points at a tie\'s metaobject holding it
define internal %Slot @t2_tie(%Array* %a, i8** %vt, %Slot %cls, %Array* %rest, %Str %ctor) {
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %cls)
  call void @t2_aappend(%Array* %args, %Array* %rest)
  %o = call %Slot @t2_tie_call(%Array* %args, %Str %ctor)
  %own = call %Meta* @t2_own_meta(%Array* %a)
  %mm = call i8* @malloc(i64 40)
  %m = bitcast i8* %mm to %Meta*
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  store i8** %vt, i8*** %vp
  %dp = getelementptr %Meta, %Meta* %m, i32 0, i32 1
  store %Slot %o, %Slot* %dp
  %sp8 = getelementptr i8, i8* %mm, i64 32
  %sp = bitcast i8* %sp8 to %Meta**
  store %Meta* %own, %Meta** %sp
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* %m, %Meta** %mp
  ret %Slot %o
}
; t2_own_meta(a) -> the metaobject a\'s own elements are read by: the default,
; or an array of aliases\' (one an element reference was taken of) -- a tie\'s
; keeps it after its own (bytes 32..39), for untie to put back.
define internal %Meta* @t2_own_meta(%Array* %a) {
entry:
  %m = call %Meta* @t2_meta(%Array* %a)
  %d = icmp eq %Meta* %m, @t2_meta_default
  %al = icmp eq %Meta* %m, @t2_meta_alias
  %hc = icmp eq %Meta* %m, @t2_meta_hcells
  %own0 = or i1 %d, %al
  %own = or i1 %own0, %hc
  br i1 %own, label %is, label %other
is:
  ret %Meta* %m
other:
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  %vt = load i8**, i8*** %vp
  %mop = icmp eq i8** %vt, getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_mophash, i64 0, i64 0)
  br i1 %mop, label %dflt, label %tied
dflt:
  ret %Meta* @t2_meta_default
tied:
  %m8 = bitcast %Meta* %m to i8*
  %sp8 = getelementptr i8, i8* %m8, i64 32
  %sp = bitcast i8* %sp8 to %Meta**
  %s = load %Meta*, %Meta** %sp
  ret %Meta* %s
}
define internal %Slot @t2_tie_array(%Array* %a, %Slot %cls, %Array* %rest) {
  %c = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_tm_tiearray, i64 0, i64 0), i64 8)
  %r = call %Slot @t2_tie(%Array* %a, i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_tiearray, i64 0, i64 0), %Slot %cls, %Array* %rest, %Str %c)
  ret %Slot %r
}
define internal %Slot @t2_tie_hash(%Slot %h, %Slot %cls, %Array* %rest) {
  %a = call %Array* @t2_harr(%Slot %h)
  %c = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_tm_tiehash, i64 0, i64 0), i64 7)
  %r = call %Slot @t2_tie(%Array* %a, i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_tiehash, i64 0, i64 0), %Slot %cls, %Array* %rest, %Str %c)
  ret %Slot %r
}
; t2_tie_scalar(cls, rest) -> cls\'s TIESCALAR(cls, rest...): a tied scalar\'s
; object (Analysis made its reads FETCH on it).
define internal %Slot @t2_tie_scalar(%Slot %cls, %Array* %rest) {
  %args = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %args, %Slot %cls)
  call void @t2_aappend(%Array* %args, %Array* %rest)
  %c = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_tm_tiescalar, i64 0, i64 0), i64 9)
  %o = call %Slot @t2_tie_call(%Array* %args, %Str %c)
  ret %Slot %o
}
; t2_tied(a) -> the tie\'s object, or undef where a has the default metaobject
define internal %Slot @t2_tied(%Array* %a) {
entry:
  %m = call %Meta* @t2_meta(%Array* %a)
  %d0 = icmp eq %Meta* %m, @t2_meta_default
  %da = icmp eq %Meta* %m, @t2_meta_alias   ; (@_ is no tie)
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  %vt = load i8**, i8*** %vp
  %dm = icmp eq i8** %vt, getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_mophash, i64 0, i64 0)   ; (nor a MOP object\'s)
  %dh = icmp eq %Meta* %m, @t2_meta_hcells   ; (nor a hash of cells)
  %d1 = or i1 %d0, %da
  %d2 = or i1 %d1, %dh
  %d = or i1 %d2, %dm
  br i1 %d, label %no, label %yes
no:
  ret %Slot zeroinitializer
yes:
  %o = call %Slot @t2_tie_obj(%Array* %a)
  ret %Slot %o
}
; t2_mop_hash(h, o): h\'s metaobject is the MOP object o (a special
; container\'s, Chalk::Impl::*): each access a call of o\'s method by the
; protocol\'s name. No tie: tied is false.
define internal void @t2_mop_hash(%Slot %h, %Slot %o) {
  %a = call %Array* @t2_harr(%Slot %h)
  %mm = call i8* @malloc(i64 32)
  %m = bitcast i8* %mm to %Meta*
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  store i8** getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_mophash, i64 0, i64 0), i8*** %vp
  %dp = getelementptr %Meta, %Meta* %m, i32 0, i32 1
  store %Slot %o, %Slot* %dp
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* %m, %Meta** %mp
  ret void
}
; t2_untie(a): a back to its own metaobject (its own elements, untouched by
; the tie: the default\'s, or an array of aliases\' -- t2_own_meta)
; (a MOP object\'s container -- %SIG -- is no tie: untie leaves it as it is, as perl\'s)
define internal void @t2_untie(%Array* %a) {
entry:
  %m = call %Meta* @t2_meta(%Array* %a)
  %vp = getelementptr %Meta, %Meta* %m, i32 0, i32 0
  %vt = load i8**, i8*** %vp
  %mop = icmp eq i8** %vt, getelementptr ([20 x i8*], [20 x i8*]* @t2_vt_mophash, i64 0, i64 0)
  br i1 %mop, label %done, label %reset
reset:
  %own = call %Meta* @t2_own_meta(%Array* %a)
  %mp = getelementptr %Array, %Array* %a, i32 0, i32 3
  store %Meta* %own, %Meta** %mp
  br label %done
done:
  ret void
}
define internal void @t2_aunshiftl_d(%Array* %a, %Array* %l) {
entry:
  %n = call i64 @t2_alen(%Array* %l)
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %l, i64 %im)
  call void @t2_aunshift_d(%Array* %a, %Slot %v)
  br label %loop
done:
  ret void
}
define internal %Slot @t2_tied_h(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  %r = call %Slot @t2_tied(%Array* %a)
  ret %Slot %r
}
define internal void @t2_untie_h(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  call void @t2_untie(%Array* %a)
  ret void
}
; t2_args_from(a, k) -> a fresh array of a\'s elements from k on (a slurpy\'s copy).
define internal %Array* @t2_args_from(%Array* %a, i64 %k) {
entry:
  %r = call %Array* @t2_new_array()
  %n = call i64 @t2_alen(%Array* %a)
  br label %loop
loop:
  %i = phi i64 [ %k, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
; t2_args_pairs(a, n): a signature\'s slurpy hash takes pairs -- an odd count
; past n is a stop (perl dies: "Odd name/value argument").
define internal void @t2_args_pairs(%Array* %a, i64 %n) {
entry:
  %got = call i64 @t2_alen(%Array* %a)
  %rest = sub i64 %got, %n
  %odd = and i64 %rest, 1
  %bad = icmp ne i64 %odd, 0
  br i1 %bad, label %stop, label %fine
stop:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)
  unreachable
fine:
  ret void
}
; t2_arity(a, off, min, max, name) -> true where a signature takes a\'s count
; past its first off (a method\'s invocant) -- max -1: no most; else perl\'s
; die, naming the sub and where it was called (@t2_call_at: a method call\'s
; site), false.
@lit_ar_few = private unnamed_addr constant [35 x i8] c"Too few arguments for subroutine \'\00"
@lit_ar_many = private unnamed_addr constant [36 x i8] c"Too many arguments for subroutine \'\00"
@lit_ar_got = private unnamed_addr constant [8 x i8] c"\' (got \00"
@lit_ar_exp = private unnamed_addr constant [12 x i8] c"; expected \00"
@lit_ar_least = private unnamed_addr constant [10 x i8] c"at least \00"
@lit_ar_most = private unnamed_addr constant [9 x i8] c"at most \00"
@lit_ar_end = private unnamed_addr constant [2 x i8] c")\00"
define internal i1 @t2_arity(%Array* %a, i64 %off, i64 %min, i64 %max, i8* %nm, i64 %nn) {
entry:
  %all = call i64 @t2_alen(%Array* %a)
  %got = sub i64 %all, %off
  %few = icmp slt i64 %got, %min
  %hasmax = icmp sge i64 %max, 0
  %over = icmp sgt i64 %got, %max
  %many = and i1 %hasmax, %over
  %bad = or i1 %few, %many
  br i1 %bad, label %die, label %ok
ok:
  ret i1 1
die:
  %hf = call %Str @t2_str(i8* getelementptr ([35 x i8], [35 x i8]* @lit_ar_few, i64 0, i64 0), i64 34)
  %hm = call %Str @t2_str(i8* getelementptr ([36 x i8], [36 x i8]* @lit_ar_many, i64 0, i64 0), i64 35)
  %h = select i1 %few, %Str %hf, %Str %hm
  %name = call %Str @t2_str(i8* %nm, i64 %nn)
  %m1 = call %Str @t2_concat(%Str %h, %Str %name)
  %gs0 = call %Str @t2_str(i8* getelementptr ([8 x i8], [8 x i8]* @lit_ar_got, i64 0, i64 0), i64 7)
  %m2 = call %Str @t2_concat(%Str %m1, %Str %gs0)
  %gn = call %Str @t2_i64_str(i64 %got)
  %m3 = call %Str @t2_concat(%Str %m2, %Str %gn)
  %es = call %Str @t2_str(i8* getelementptr ([12 x i8], [12 x i8]* @lit_ar_exp, i64 0, i64 0), i64 11)
  %m4 = call %Str @t2_concat(%Str %m3, %Str %es)
  %exact = icmp eq i64 %min, %max
  %ql = call %Str @t2_str(i8* getelementptr ([10 x i8], [10 x i8]* @lit_ar_least, i64 0, i64 0), i64 9)
  %qm = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_ar_most, i64 0, i64 0), i64 8)
  %qn = call %Str @t2_str(i8* getelementptr ([9 x i8], [9 x i8]* @lit_ar_most, i64 0, i64 0), i64 0)
  %q0 = select i1 %few, %Str %ql, %Str %qm
  %q = select i1 %exact, %Str %qn, %Str %q0
  %m5 = call %Str @t2_concat(%Str %m4, %Str %q)
  %want = select i1 %few, i64 %min, i64 %max
  %wn = call %Str @t2_i64_str(i64 %want)
  %m6 = call %Str @t2_concat(%Str %m5, %Str %wn)
  %en = call %Str @t2_str(i8* getelementptr ([2 x i8], [2 x i8]* @lit_ar_end, i64 0, i64 0), i64 1)
  %m7 = call %Str @t2_concat(%Str %m6, %Str %en)
  %at = load %Str, %Str* @t2_call_at
  %m = call %Str @t2_concat(%Str %m7, %Str %at)
  call void @t2_die_unwind(%Str %m)
  ret i1 0
}
; t2_args_min(a, n): a signature\'s arity -- at least n arguments, else a stop.
define internal void @t2_args_min(%Array* %a, i64 %n) {
entry:
  %got = call i64 @t2_alen(%Array* %a)
  %ok = icmp sge i64 %got, %n
  br i1 %ok, label %fine, label %bad
bad:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)
  unreachable
fine:
  ret void
}
; t2_args_max(a, n): a signature\'s arity -- at most n arguments, else a stop.
define internal void @t2_args_max(%Array* %a, i64 %n) {
entry:
  %got = call i64 @t2_alen(%Array* %a)
  %ok = icmp sle i64 %got, %n
  br i1 %ok, label %fine, label %bad
bad:
  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)
  unreachable
fine:
  ret void
}
; t2_slot_ncmp(x, y) -> perl\'s <=> (do_ncmp): -1, 0, 1, or 2 where an NV is
; NaN. Two integers (as perl reads them: t2_arith_num) exactly -- an IV and
; a UV, past 2**53 too, where a double cannot tell them apart -- else their NVs.
define internal i64 @t2_slot_ncmp(%Slot %x0, %Slot %y0) {
entry:
  %y = call %Slot @t2_arith_num(%Slot %y0)
  %x = call %Slot @t2_arith_num(%Slot %x0)
  %tx = extractvalue %Slot %x, 0
  %ty = extractvalue %Slot %y, 0
  %nx = icmp eq i8 %tx, 2
  %ny = icmp eq i8 %ty, 2
  %either = or i1 %nx, %ny
  br i1 %either, label %nums, label %ints
ints:
  %wx = call i128 @t2_wide(%Slot %x)
  %wy = call i128 @t2_wide(%Slot %y)
  %ilt = icmp slt i128 %wx, %wy
  %igt = icmp sgt i128 %wx, %wy
  %il = select i1 %ilt, i64 -1, i64 0
  %ir = select i1 %igt, i64 1, i64 %il
  ret i64 %ir
nums:
  %dx = call double @t2_slot_num(%Slot %x)
  %dy = call double @t2_slot_num(%Slot %y)
  %lt = fcmp olt double %dx, %dy
  %gt = fcmp ogt double %dx, %dy
  %eq = fcmp oeq double %dx, %dy
  %u = select i1 %eq, i64 0, i64 2
  %l = select i1 %lt, i64 -1, i64 %u
  %r = select i1 %gt, i64 1, i64 %l
  ret i64 %r
}
; t2_slot_numcmp(x, y, op) -> perl\'s numeric comparison op of two scalars, on
; t2_slot_ncmp: 0 ==, 1 !=, 2 <, 3 >, 4 <=, 5 >= (a NaN false, but != true).
define internal i1 @t2_slot_numcmp(%Slot %x, %Slot %y, i64 %op) {
entry:
  %c = call i64 @t2_slot_ncmp(%Slot %x, %Slot %y)
  %eq = icmp eq i64 %c, 0
  %lt = icmp eq i64 %c, -1
  %gt = icmp eq i64 %c, 1
  %ne = xor i1 %eq, true
  %le = or i1 %lt, %eq
  %ge = or i1 %gt, %eq
  switch i64 %op, label %r0 [ i64 1, label %r1
                              i64 2, label %r2
                              i64 3, label %r3
                              i64 4, label %r4
                              i64 5, label %r5 ]
r0:
  ret i1 %eq
r1:
  ret i1 %ne
r2:
  ret i1 %lt
r3:
  ret i1 %gt
r4:
  ret i1 %le
r5:
  ret i1 %ge
}
; t2_cmp(x, y, num) -> perl\'s cmp (by string) or <=> (by number): -1, 0, 1
; (a NaN 0, where perl\'s sort is undefined).
define internal i64 @t2_cmp(%Slot %x, %Slot %y, i1 %num) {
entry:
  br i1 %num, label %n, label %s
n:
  %cn = call i64 @t2_slot_ncmp(%Slot %x, %Slot %y)
  %nan = icmp eq i64 %cn, 2
  %c0 = select i1 %nan, i64 0, i64 %cn
  ret i64 %c0
s:
  %sx = call %Str @t2_slot_str(%Slot %x)
  %sy = call %Str @t2_slot_str(%Slot %y)
  %c = call i64 @t2_strcmp(%Str %sx, %Str %sy)
  %neg = icmp slt i64 %c, 0
  %pos = icmp sgt i64 %c, 0
  %c1 = select i1 %neg, i64 -1, i64 0
  %c2 = select i1 %pos, i64 1, i64 %c1
  ret i64 %c2
}
; t2_hderef_r(r) -> the hash r holds, read whole; undef an empty hash (perl\'s
; rvalue +(undef)->%*). What is not a hash stops at its first access.
define internal %Slot @t2_hderef_r(%Slot %r) {
entry:
  %t = extractvalue %Slot %r, 0
  %u = icmp eq i8 %t, 0
  br i1 %u, label %empty, label %as
empty:
  %h = call %Slot @t2_hnew()
  ret %Slot %h
as:
  ret %Slot %r
}
; t2_asort(a, num, desc) -> a new list of a\'s elements in order (stable, as
; perl\'s mergesort is).
define internal %Array* @t2_asort(%Array* %a, i1 %num, i1 %desc) {
entry:
  %r = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %r, %Array* %a)
  %n = call i64 @t2_alen(%Array* %r)
  br label %outer
outer:
  %i = phi i64 [ 1, %entry ], [ %i2, %placed ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %take, label %done
take:
  %v = call %Slot @t2_aget(%Array* %r, i64 %i)
  br label %inner
inner:
  %j = phi i64 [ %i, %take ], [ %jm, %shift ]
  %atstart = icmp eq i64 %j, 0
  br i1 %atstart, label %place, label %look
look:
  %jm = sub i64 %j, 1
  %p = call %Slot @t2_aget(%Array* %r, i64 %jm)
  %c0 = call i64 @t2_cmp(%Slot %p, %Slot %v, i1 %num)
  %cn = sub i64 0, %c0
  %c = select i1 %desc, i64 %cn, i64 %c0
  %after = icmp sgt i64 %c, 0
  br i1 %after, label %shift, label %place
shift:
  call void @t2_aset(%Array* %r, i64 %j, %Slot %p, i8* null, i64 0)
  br label %inner
place:
  call void @t2_aset(%Array* %r, i64 %j, %Slot %v, i8* null, i64 0)
  br label %placed
placed:
  %i2 = add i64 %i, 1
  br label %outer
done:
  ret %Array* %r
}
; t2_asort_by(a, f, ga, gb) -> a new list of a\'s elements in the order f
; gives: for each pair $a (ga) and $b (gb) are set, f called, and a number
; above 0 puts $a after $b (stable). $a and $b are as they were after.
@t2_cmp_env = internal global %Array* null
define internal %Slot @t2_cmp_env_at(i64 %i) {
  %e = load %Array*, %Array** @t2_cmp_env
  %s = call %Slot @t2_aget(%Array* %e, i64 %i)
  ret %Slot %s
}
@t2_cur_cmp = internal global %Slot ()* null
@t2_cur_ga = internal global %Slot* null
@t2_cur_gb = internal global %Slot* null
; t2_sort_cmp_ab(a, b): the comparator on a pair -- $a and $b set, it called,
; its number given; one that dies leaves the sort (t2_msort_abort).
define double @t2_sort_cmp_ab(%Slot* %a, %Slot* %b) {
entry:
  %ga = load %Slot*, %Slot** @t2_cur_ga
  %gb = load %Slot*, %Slot** @t2_cur_gb
  %va = load %Slot, %Slot* %a
  %vb = load %Slot, %Slot* %b
  store %Slot %va, %Slot* %ga
  store %Slot %vb, %Slot* %gb
  %f = load %Slot ()*, %Slot ()** @t2_cur_cmp
  %c = call %Slot %f()
  %d = load i1, i1* @t2_dying
  br i1 %d, label %die, label %ok
die:
  call void @t2_msort_abort()
  unreachable
ok:
  %n = call double @t2_slot_num(%Slot %c)
  ret double %n
}
; t2_asort_by(a, env, f, ga, gb) -> a new list of a\'s elements in the order
; f gives, compared as perl\'s sort compares (pp_sort.c, ported: t2_msort) --
; the same pairs in the same order, so a comparator\'s effects are perl\'s.
; $a, $b, the env and the comparator are as they were after.
define internal %Array* @t2_asort_by(%Array* %a, %Array* %env, %Slot ()* %f, %Slot* %ga, %Slot* %gb) {
entry:
  %oe = load %Array*, %Array** @t2_cmp_env
  %oa = load %Slot, %Slot* %ga
  %ob = load %Slot, %Slot* %gb
  %of = load %Slot ()*, %Slot ()** @t2_cur_cmp
  %oga = load %Slot*, %Slot** @t2_cur_ga
  %ogb = load %Slot*, %Slot** @t2_cur_gb
  store %Array* %env, %Array** @t2_cmp_env
  store %Slot ()* %f, %Slot ()** @t2_cur_cmp
  store %Slot* %ga, %Slot** @t2_cur_ga
  store %Slot* %gb, %Slot** @t2_cur_gb
  %r = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %r, %Array* %a)
  %n = call i64 @t2_alen(%Array* %r)
  %ep = getelementptr %Array, %Array* %r, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %died = call i32 @t2_msort(%Slot* %els, i64 %n)
  store %Slot %oa, %Slot* %ga
  store %Slot %ob, %Slot* %gb
  store %Slot ()* %of, %Slot ()** @t2_cur_cmp
  store %Slot* %oga, %Slot** @t2_cur_ga
  store %Slot* %ogb, %Slot** @t2_cur_gb
  store %Array* %oe, %Array** @t2_cmp_env
  ret %Array* %r
}
; ---- perl\'s sort, ported to C (pp_sort.c\'s dynprep and merge) and compiled ----

%struct.off_runs = type { i64, i64 }
%struct.__jmp_buf_tag = type { [8 x i64], i32, %struct.__sigset_t }
%struct.__sigset_t = type { [16 x i64] }
%struct.Slot = type { i8, i64 }

@msort_jb = internal unnamed_addr global ptr null, align 8

; Function Attrs: noreturn nounwind uwtable
define dso_local void @t2_msort_abort() local_unnamed_addr #0 {
  %1 = load ptr, ptr @msort_jb, align 8
  tail call void @longjmp(ptr noundef %1, i32 noundef 1) #10
  unreachable
}

; Function Attrs: noreturn nounwind
declare void @longjmp(ptr noundef, i32 noundef) local_unnamed_addr #1

; Function Attrs: nounwind uwtable
define dso_local noundef i32 @t2_msort(ptr nocapture noundef %0, i64 noundef %1) local_unnamed_addr #2 {
  %3 = alloca [200 x ptr], align 16
  %4 = alloca [3 x ptr], align 16
  %5 = alloca [60 x %struct.off_runs], align 16
  %6 = alloca [1 x %struct.__jmp_buf_tag], align 16
  %7 = call i64 @llvm.umax.i64(i64 %1, i64 1)
  %8 = shl i64 %7, 3
  %9 = call noalias ptr @malloc(i64 noundef %8) #11
  %10 = shl i64 %7, 4
  %11 = call noalias ptr @malloc(i64 noundef %10) #11
  call void @llvm.lifetime.start.p0(i64 200, ptr nonnull %6) #12
  %12 = load ptr, ptr @msort_jb, align 8
  %13 = icmp sgt i64 %1, 0
  br i1 %13, label %14, label %16

14:                                               ; preds = %2
  %15 = shl nuw i64 %1, 4
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %11, ptr align 8 %0, i64 %15, i1 false)
  br label %19

16:                                               ; preds = %19, %2
  store ptr %6, ptr @msort_jb, align 8
  %17 = call i32 @_setjmp(ptr noundef nonnull %6) #13
  %18 = icmp eq i32 %17, 0
  br i1 %18, label %25, label %508

19:                                               ; preds = %14, %19
  %20 = phi i64 [ %23, %19 ], [ 0, %14 ]
  %21 = getelementptr inbounds %struct.Slot, ptr %11, i64 %20
  %22 = getelementptr inbounds ptr, ptr %9, i64 %20
  store ptr %21, ptr %22, align 8
  %23 = add nuw nsw i64 %20, 1
  %24 = icmp eq i64 %23, %1
  br i1 %24, label %16, label %19

25:                                               ; preds = %16
  %26 = ptrtoint ptr %9 to i64
  call void @llvm.lifetime.start.p0(i64 1600, ptr nonnull %3) #12
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %4) #12
  call void @llvm.lifetime.start.p0(i64 960, ptr nonnull %5) #12
  %27 = icmp ult i64 %1, 2
  br i1 %27, label %499, label %28

28:                                               ; preds = %25
  %29 = icmp ult i64 %1, 201
  br i1 %29, label %33, label %30

30:                                               ; preds = %28
  %31 = shl i64 %1, 3
  %32 = call noalias ptr @malloc(i64 noundef %31) #11
  br label %33

33:                                               ; preds = %30, %28
  %34 = phi ptr [ %32, %30 ], [ %3, %28 ]
  %35 = getelementptr inbounds ptr, ptr %9, i64 %1
  %36 = load ptr, ptr %9, align 8
  %37 = getelementptr inbounds ptr, ptr %9, i64 1
  %38 = load ptr, ptr %37, align 8
  %39 = call double @t2_sort_cmp_ab(ptr noundef %36, ptr noundef %38) #12
  %40 = icmp sgt i64 %1, 0
  br i1 %40, label %41, label %192

41:                                               ; preds = %33
  %42 = fcmp oge double %39, 9.200000e+18
  %43 = fcmp ugt double %39, -9.200000e+18
  %44 = fptosi double %39 to i64
  %45 = icmp sgt i64 %44, 0
  %46 = select i1 %43, i1 %45, i1 false
  %47 = select i1 %42, i1 true, i1 %46
  br label %48

48:                                               ; preds = %189, %41
  %49 = phi i1 [ %190, %189 ], [ %47, %41 ]
  %50 = phi ptr [ %187, %189 ], [ %9, %41 ]
  %51 = phi i64 [ %186, %189 ], [ 0, %41 ]
  %52 = phi ptr [ %177, %189 ], [ %34, %41 ]
  br label %53

53:                                               ; preds = %58, %48
  %54 = phi ptr [ %55, %58 ], [ %50, %48 ]
  %55 = getelementptr inbounds ptr, ptr %54, i64 2
  %56 = getelementptr inbounds ptr, ptr %54, i64 3
  %57 = icmp ult ptr %56, %35
  br i1 %57, label %58, label %69

58:                                               ; preds = %53
  %59 = load ptr, ptr %55, align 8
  %60 = load ptr, ptr %56, align 8
  %61 = call double @t2_sort_cmp_ab(ptr noundef %59, ptr noundef %60) #12
  %62 = fcmp ult double %61, 9.200000e+18
  %63 = fcmp ole double %61, -9.200000e+18
  %64 = fptosi double %61 to i64
  %65 = icmp slt i64 %64, 1
  %66 = select i1 %63, i1 true, i1 %65
  %67 = select i1 %62, i1 %66, i1 false
  %68 = xor i1 %49, %67
  br i1 %68, label %53, label %69

69:                                               ; preds = %58, %53
  %70 = icmp eq ptr %56, %35
  br label %71

71:                                               ; preds = %185, %69
  %72 = phi ptr [ %50, %69 ], [ %160, %185 ]
  %73 = phi ptr [ %52, %69 ], [ %177, %185 ]
  %74 = phi i64 [ %51, %69 ], [ %186, %185 ]
  %75 = phi ptr [ %50, %69 ], [ %187, %185 ]
  %76 = getelementptr inbounds ptr, ptr %75, i64 16
  %77 = icmp ult ptr %76, %55
  br i1 %77, label %78, label %113

78:                                               ; preds = %71, %91
  %79 = phi ptr [ %92, %91 ], [ %76, %71 ]
  %80 = getelementptr inbounds ptr, ptr %79, i64 -1
  %81 = load ptr, ptr %80, align 8
  %82 = load ptr, ptr %79, align 8
  %83 = call double @t2_sort_cmp_ab(ptr noundef %81, ptr noundef %82) #12
  %84 = fcmp ult double %83, 9.200000e+18
  %85 = fcmp ole double %83, -9.200000e+18
  %86 = fptosi double %83 to i64
  %87 = icmp slt i64 %86, 1
  %88 = select i1 %85, i1 true, i1 %87
  %89 = select i1 %84, i1 %88, i1 false
  %90 = xor i1 %49, %89
  br i1 %90, label %91, label %94

91:                                               ; preds = %78
  %92 = getelementptr inbounds ptr, ptr %79, i64 -2
  %93 = icmp ugt ptr %92, %72
  br i1 %93, label %78, label %94

94:                                               ; preds = %91, %78
  %95 = phi ptr [ %92, %91 ], [ %79, %78 ]
  %96 = icmp ugt ptr %95, %72
  br i1 %96, label %113, label %97

97:                                               ; preds = %94, %101
  %98 = phi ptr [ %99, %101 ], [ %76, %94 ]
  %99 = getelementptr inbounds ptr, ptr %98, i64 2
  %100 = icmp ult ptr %98, %54
  br i1 %100, label %101, label %113

101:                                              ; preds = %97
  %102 = getelementptr inbounds ptr, ptr %98, i64 1
  %103 = load ptr, ptr %102, align 8
  %104 = load ptr, ptr %99, align 8
  %105 = call double @t2_sort_cmp_ab(ptr noundef %103, ptr noundef %104) #12
  %106 = fcmp ult double %105, 9.200000e+18
  %107 = fcmp ole double %105, -9.200000e+18
  %108 = fptosi double %105 to i64
  %109 = icmp slt i64 %108, 1
  %110 = select i1 %107, i1 true, i1 %109
  %111 = select i1 %106, i1 %110, i1 false
  %112 = xor i1 %49, %111
  br i1 %112, label %97, label %113

113:                                              ; preds = %101, %97, %94, %71
  %114 = phi ptr [ %72, %94 ], [ %72, %71 ], [ %98, %97 ], [ %98, %101 ]
  %115 = phi ptr [ %95, %94 ], [ %55, %71 ], [ %99, %97 ], [ %99, %101 ]
  %116 = phi ptr [ %76, %94 ], [ %55, %71 ], [ %99, %97 ], [ %99, %101 ]
  %117 = icmp ugt ptr %114, %75
  br i1 %117, label %118, label %156

118:                                              ; preds = %113
  %119 = getelementptr inbounds ptr, ptr %114, i64 2
  %120 = icmp eq ptr %114, %54
  %121 = select i1 %120, i1 %70, i1 false
  br i1 %121, label %122, label %135

122:                                              ; preds = %118
  %123 = getelementptr inbounds ptr, ptr %114, i64 1
  %124 = load ptr, ptr %123, align 8
  %125 = load ptr, ptr %119, align 8
  %126 = call double @t2_sort_cmp_ab(ptr noundef %124, ptr noundef %125) #12
  %127 = fcmp ult double %126, 9.200000e+18
  %128 = fcmp ole double %126, -9.200000e+18
  %129 = fptosi double %126 to i64
  %130 = icmp slt i64 %129, 1
  %131 = select i1 %128, i1 true, i1 %130
  %132 = select i1 %127, i1 %131, i1 false
  %133 = xor i1 %49, %132
  br i1 %133, label %134, label %135

134:                                              ; preds = %122
  br label %135

135:                                              ; preds = %134, %122, %118
  %136 = phi ptr [ %35, %134 ], [ %119, %122 ], [ %119, %118 ]
  %137 = phi ptr [ %35, %134 ], [ %116, %122 ], [ %116, %118 ]
  %138 = phi ptr [ %35, %134 ], [ %115, %122 ], [ %115, %118 ]
  %139 = ptrtoint ptr %136 to i64
  %140 = ptrtoint ptr %75 to i64
  %141 = sub i64 %139, %140
  %142 = ashr exact i64 %141, 3
  %143 = getelementptr inbounds ptr, ptr %73, i64 %142
  store ptr %143, ptr %73, align 8
  %144 = add nsw i64 %74, 1
  %145 = getelementptr inbounds ptr, ptr %136, i64 -1
  %146 = icmp ult ptr %75, %145
  %147 = select i1 %49, i1 %146, i1 false
  br i1 %147, label %148, label %156

148:                                              ; preds = %135, %148
  %149 = phi ptr [ %154, %148 ], [ %145, %135 ]
  %150 = phi ptr [ %153, %148 ], [ %75, %135 ]
  %151 = load ptr, ptr %150, align 8
  %152 = load ptr, ptr %149, align 8
  %153 = getelementptr inbounds ptr, ptr %150, i64 1
  store ptr %152, ptr %150, align 8
  store ptr %151, ptr %149, align 8
  %154 = getelementptr inbounds ptr, ptr %149, i64 -1
  %155 = icmp ult ptr %153, %154
  br i1 %155, label %148, label %156

156:                                              ; preds = %148, %135, %113
  %157 = phi ptr [ %114, %113 ], [ %136, %135 ], [ %136, %148 ]
  %158 = phi ptr [ %73, %113 ], [ %143, %135 ], [ %143, %148 ]
  %159 = phi ptr [ %115, %113 ], [ %138, %135 ], [ %138, %148 ]
  %160 = phi ptr [ %116, %113 ], [ %137, %135 ], [ %137, %148 ]
  %161 = phi i64 [ %74, %113 ], [ %144, %135 ], [ %144, %148 ]
  %162 = icmp ult ptr %157, %159
  br i1 %162, label %163, label %176

163:                                              ; preds = %156, %173
  %164 = phi i64 [ %168, %173 ], [ %161, %156 ]
  %165 = phi ptr [ %167, %173 ], [ %158, %156 ]
  %166 = phi ptr [ %174, %173 ], [ %157, %156 ]
  %167 = getelementptr inbounds ptr, ptr %165, i64 2
  store ptr %167, ptr %165, align 8
  %168 = add nsw i64 %164, 1
  br i1 %49, label %169, label %173

169:                                              ; preds = %163
  %170 = getelementptr inbounds ptr, ptr %166, i64 1
  %171 = load ptr, ptr %166, align 8
  %172 = load ptr, ptr %170, align 8
  store ptr %172, ptr %166, align 8
  store ptr %171, ptr %170, align 8
  br label %173

173:                                              ; preds = %169, %163
  %174 = getelementptr inbounds ptr, ptr %166, i64 2
  %175 = icmp ult ptr %174, %159
  br i1 %175, label %163, label %176

176:                                              ; preds = %173, %156
  %177 = phi ptr [ %158, %156 ], [ %167, %173 ]
  %178 = phi i64 [ %161, %156 ], [ %168, %173 ]
  %179 = icmp eq ptr %159, %55
  %180 = select i1 %179, i1 %70, i1 false
  br i1 %180, label %181, label %185

181:                                              ; preds = %176
  %182 = getelementptr inbounds ptr, ptr %177, i64 1
  store ptr %182, ptr %177, align 8
  %183 = add nsw i64 %178, 1
  %184 = getelementptr inbounds ptr, ptr %159, i64 1
  br label %185

185:                                              ; preds = %181, %176
  %186 = phi i64 [ %183, %181 ], [ %178, %176 ]
  %187 = phi ptr [ %184, %181 ], [ %159, %176 ]
  %188 = icmp ult ptr %187, %55
  br i1 %188, label %71, label %189

189:                                              ; preds = %185
  %190 = xor i1 %49, true
  %191 = icmp ult ptr %187, %35
  br i1 %191, label %48, label %192

192:                                              ; preds = %189, %33
  %193 = phi i64 [ 0, %33 ], [ %186, %189 ]
  %194 = getelementptr inbounds %struct.off_runs, ptr %5, i64 0, i32 1
  store i64 %193, ptr %194, align 8
  store i64 0, ptr %5, align 16
  %195 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 2
  store ptr %9, ptr %195, align 16
  store ptr %9, ptr %4, align 16
  %196 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 1
  store ptr %34, ptr %196, align 8
  %197 = ptrtoint ptr %34 to i64
  %198 = xor i64 %26, -1
  %199 = sub i64 %26, %197
  %200 = add i64 %26, 8
  br label %201

201:                                              ; preds = %491, %192
  %202 = phi i64 [ 0, %192 ], [ %492, %491 ]
  %203 = phi i32 [ 0, %192 ], [ %493, %491 ]
  %204 = phi ptr [ %5, %192 ], [ %494, %491 ]
  %205 = getelementptr inbounds %struct.off_runs, ptr %204, i64 0, i32 1
  %206 = load i64, ptr %205, align 8
  %207 = icmp eq i64 %206, 0
  br i1 %207, label %208, label %422

208:                                              ; preds = %201
  %209 = and i32 %203, 1
  %210 = zext nneg i32 %209 to i64
  %211 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 %210
  %212 = load ptr, ptr %211, align 8
  %213 = add nuw nsw i32 %209, 1
  %214 = zext nneg i32 %213 to i64
  %215 = getelementptr inbounds [3 x ptr], ptr %4, i64 0, i64 %214
  %216 = load ptr, ptr %215, align 8
  br label %217

217:                                              ; preds = %412, %208
  %218 = phi i32 [ %203, %208 ], [ %403, %412 ]
  %219 = phi ptr [ %204, %208 ], [ %408, %412 ]
  %220 = phi ptr [ %212, %208 ], [ %410, %412 ]
  %221 = phi ptr [ %216, %208 ], [ %411, %412 ]
  %222 = load i64, ptr %219, align 8
  %223 = getelementptr inbounds ptr, ptr %220, i64 %222
  %224 = getelementptr inbounds ptr, ptr %221, i64 %222
  %225 = load ptr, ptr %224, align 8
  %226 = ptrtoint ptr %225 to i64
  %227 = ptrtoint ptr %221 to i64
  %228 = sub i64 %226, %227
  %229 = getelementptr inbounds i8, ptr %220, i64 %228
  %230 = load ptr, ptr %225, align 8
  %231 = ptrtoint ptr %230 to i64
  %232 = sub i64 %231, %227
  %233 = getelementptr inbounds i8, ptr %220, i64 %232
  %234 = icmp ult ptr %223, %229
  %235 = icmp slt i64 %228, %232
  %236 = select i1 %234, i1 %235, i1 false
  br i1 %236, label %237, label %377

237:                                              ; preds = %217, %366
  %238 = phi ptr [ %373, %366 ], [ %224, %217 ]
  %239 = phi ptr [ %370, %366 ], [ %229, %217 ]
  %240 = phi ptr [ %369, %366 ], [ %223, %217 ]
  %241 = load ptr, ptr %240, align 8
  %242 = load ptr, ptr %239, align 8
  %243 = call double @t2_sort_cmp_ab(ptr noundef %241, ptr noundef %242) #12
  %244 = fcmp ult double %243, 9.200000e+18
  %245 = fcmp ole double %243, -9.200000e+18
  %246 = fptosi double %243 to i64
  %247 = icmp slt i64 %246, 1
  %248 = select i1 %245, i1 true, i1 %247
  %249 = select i1 %244, i1 %248, i1 false
  %250 = sext i1 %249 to i32
  %251 = select i1 %249, ptr %229, ptr %233
  %252 = select i1 %249, ptr %240, ptr %239
  %253 = select i1 %249, ptr %239, ptr %240
  %254 = getelementptr inbounds ptr, ptr %252, i64 1
  %255 = icmp ult ptr %254, %251
  br i1 %255, label %256, label %270

256:                                              ; preds = %237
  %257 = load ptr, ptr %253, align 8
  %258 = load ptr, ptr %254, align 8
  %259 = call double @t2_sort_cmp_ab(ptr noundef %257, ptr noundef %258) #12
  %260 = fcmp ult double %259, 9.200000e+18
  %261 = fcmp ole double %259, -9.200000e+18
  %262 = fptosi double %259 to i64
  %263 = select i1 %261, i64 -1, i64 %262
  %264 = select i1 %260, i64 %263, i64 1
  %265 = icmp sgt i64 %264, -1
  %266 = icmp ne i64 %264, 0
  %267 = zext i1 %266 to i32
  %268 = icmp sgt i32 %267, %250
  %269 = and i1 %265, %268
  br i1 %269, label %304, label %313

270:                                              ; preds = %304, %237
  %271 = phi ptr [ %252, %237 ], [ %307, %304 ]
  %272 = getelementptr inbounds ptr, ptr %251, i64 -1
  %273 = icmp ugt ptr %272, %271
  br i1 %273, label %274, label %288

274:                                              ; preds = %270
  %275 = load ptr, ptr %253, align 8
  %276 = load ptr, ptr %272, align 8
  %277 = call double @t2_sort_cmp_ab(ptr noundef %275, ptr noundef %276) #12
  %278 = fcmp ult double %277, 9.200000e+18
  %279 = fcmp ole double %277, -9.200000e+18
  %280 = fptosi double %277 to i64
  %281 = select i1 %279, i64 -1, i64 %280
  %282 = select i1 %278, i64 %281, i64 1
  %283 = icmp sgt i64 %282, -1
  %284 = icmp ne i64 %282, 0
  %285 = zext i1 %284 to i32
  %286 = icmp sgt i32 %285, %250
  %287 = and i1 %283, %286
  br i1 %287, label %288, label %313

288:                                              ; preds = %274, %270
  br label %313

289:                                              ; preds = %304
  %290 = add nuw nsw i64 %305, 1
  %291 = load ptr, ptr %253, align 8
  %292 = load ptr, ptr %311, align 8
  %293 = call double @t2_sort_cmp_ab(ptr noundef %291, ptr noundef %292) #12
  %294 = fcmp ult double %293, 9.200000e+18
  %295 = fcmp ole double %293, -9.200000e+18
  %296 = fptosi double %293 to i64
  %297 = select i1 %295, i64 -1, i64 %296
  %298 = select i1 %294, i64 %297, i64 1
  %299 = icmp sgt i64 %298, -1
  %300 = icmp ne i64 %298, 0
  %301 = zext i1 %300 to i32
  %302 = icmp sgt i32 %301, %250
  %303 = and i1 %299, %302
  br i1 %303, label %304, label %313

304:                                              ; preds = %256, %289
  %305 = phi i64 [ %290, %289 ], [ 0, %256 ]
  %306 = phi i64 [ %310, %289 ], [ 1, %256 ]
  %307 = phi ptr [ %311, %289 ], [ %254, %256 ]
  %308 = icmp ugt i64 %305, 4
  %309 = zext i1 %308 to i64
  %310 = shl nsw i64 %306, %309
  %311 = getelementptr inbounds ptr, ptr %307, i64 %310
  %312 = icmp ult ptr %311, %251
  br i1 %312, label %289, label %270

313:                                              ; preds = %289, %256, %288, %274
  %314 = phi ptr [ %251, %288 ], [ %272, %274 ], [ %254, %256 ], [ %311, %289 ]
  %315 = phi ptr [ %272, %288 ], [ %271, %274 ], [ %252, %256 ], [ %307, %289 ]
  %316 = getelementptr inbounds ptr, ptr %315, i64 1
  %317 = icmp ult ptr %316, %314
  br i1 %317, label %318, label %345

318:                                              ; preds = %313, %318
  %319 = phi ptr [ %343, %318 ], [ %316, %313 ]
  %320 = phi ptr [ %342, %318 ], [ %314, %313 ]
  %321 = ptrtoint ptr %320 to i64
  %322 = ptrtoint ptr %319 to i64
  %323 = sub i64 %321, %322
  %324 = ashr exact i64 %323, 3
  %325 = add nsw i64 %324, -1
  %326 = sdiv i64 %325, 2
  %327 = getelementptr inbounds ptr, ptr %319, i64 %326
  %328 = load ptr, ptr %253, align 8
  %329 = load ptr, ptr %327, align 8
  %330 = call double @t2_sort_cmp_ab(ptr noundef %328, ptr noundef %329) #12
  %331 = fcmp ult double %330, 9.200000e+18
  %332 = fcmp ole double %330, -9.200000e+18
  %333 = fptosi double %330 to i64
  %334 = select i1 %332, i64 -1, i64 %333
  %335 = select i1 %331, i64 %334, i64 1
  %336 = icmp sgt i64 %335, -1
  %337 = icmp ne i64 %335, 0
  %338 = zext i1 %337 to i32
  %339 = icmp sgt i32 %338, %250
  %340 = and i1 %336, %339
  %341 = getelementptr inbounds ptr, ptr %327, i64 1
  %342 = select i1 %340, ptr %320, ptr %327
  %343 = select i1 %340, ptr %341, ptr %319
  %344 = icmp ult ptr %343, %342
  br i1 %344, label %318, label %345

345:                                              ; preds = %318, %313
  %346 = phi ptr [ %314, %313 ], [ %342, %318 ]
  %347 = icmp eq ptr %253, %240
  br i1 %347, label %348, label %357

348:                                              ; preds = %345, %348
  %349 = phi ptr [ %351, %348 ], [ %239, %345 ]
  %350 = phi ptr [ %353, %348 ], [ %238, %345 ]
  %351 = getelementptr inbounds ptr, ptr %349, i64 1
  %352 = load ptr, ptr %349, align 8
  %353 = getelementptr inbounds ptr, ptr %350, i64 1
  store ptr %352, ptr %350, align 8
  %354 = icmp ult ptr %351, %346
  br i1 %354, label %348, label %355

355:                                              ; preds = %348
  %356 = getelementptr inbounds ptr, ptr %240, i64 1
  br label %366

357:                                              ; preds = %345, %357
  %358 = phi ptr [ %360, %357 ], [ %240, %345 ]
  %359 = phi ptr [ %362, %357 ], [ %238, %345 ]
  %360 = getelementptr inbounds ptr, ptr %358, i64 1
  %361 = load ptr, ptr %358, align 8
  %362 = getelementptr inbounds ptr, ptr %359, i64 1
  store ptr %361, ptr %359, align 8
  %363 = icmp ult ptr %360, %346
  br i1 %363, label %357, label %364

364:                                              ; preds = %357
  %365 = getelementptr inbounds ptr, ptr %239, i64 1
  br label %366

366:                                              ; preds = %364, %355
  %367 = phi ptr [ %239, %364 ], [ %240, %355 ]
  %368 = phi ptr [ %362, %364 ], [ %353, %355 ]
  %369 = phi ptr [ %360, %364 ], [ %356, %355 ]
  %370 = phi ptr [ %365, %364 ], [ %351, %355 ]
  %371 = phi ptr [ %359, %364 ], [ %350, %355 ]
  %372 = load ptr, ptr %367, align 8
  store ptr %372, ptr %368, align 8
  %373 = getelementptr inbounds ptr, ptr %371, i64 2
  %374 = icmp ult ptr %369, %229
  %375 = icmp ult ptr %370, %233
  %376 = select i1 %374, i1 %375, i1 false
  br i1 %376, label %237, label %377

377:                                              ; preds = %366, %217
  %378 = phi ptr [ %223, %217 ], [ %369, %366 ]
  %379 = phi ptr [ %229, %217 ], [ %370, %366 ]
  %380 = phi ptr [ %224, %217 ], [ %373, %366 ]
  %381 = phi i1 [ %235, %217 ], [ %375, %366 ]
  %382 = icmp eq ptr %378, %229
  br i1 %382, label %383, label %391

383:                                              ; preds = %377
  br i1 %381, label %384, label %398

384:                                              ; preds = %383, %384
  %385 = phi ptr [ %387, %384 ], [ %379, %383 ]
  %386 = phi ptr [ %389, %384 ], [ %380, %383 ]
  %387 = getelementptr inbounds ptr, ptr %385, i64 1
  %388 = load ptr, ptr %385, align 8
  %389 = getelementptr inbounds ptr, ptr %386, i64 1
  store ptr %388, ptr %386, align 8
  %390 = icmp ult ptr %387, %233
  br i1 %390, label %384, label %398

391:                                              ; preds = %377, %391
  %392 = phi ptr [ %394, %391 ], [ %378, %377 ]
  %393 = phi ptr [ %396, %391 ], [ %380, %377 ]
  %394 = getelementptr inbounds ptr, ptr %392, i64 1
  %395 = load ptr, ptr %392, align 8
  %396 = getelementptr inbounds ptr, ptr %393, i64 1
  store ptr %395, ptr %393, align 8
  %397 = icmp ult ptr %394, %229
  br i1 %397, label %391, label %398

398:                                              ; preds = %391, %384, %383
  %399 = phi ptr [ %380, %383 ], [ %389, %384 ], [ %396, %391 ]
  %400 = ptrtoint ptr %399 to i64
  %401 = sub i64 %400, %227
  %402 = getelementptr inbounds i8, ptr %220, i64 %401
  store ptr %402, ptr %223, align 8
  %403 = add nsw i32 %218, -1
  %404 = icmp eq i32 %403, 0
  br i1 %404, label %407, label %405

405:                                              ; preds = %398
  %406 = getelementptr inbounds %struct.off_runs, ptr %219, i64 -1
  br label %407

407:                                              ; preds = %405, %398
  %408 = phi ptr [ %406, %405 ], [ %219, %398 ]
  %409 = phi i32 [ 0, %405 ], [ 20, %398 ]
  %410 = phi ptr [ %221, %405 ], [ %220, %398 ]
  %411 = phi ptr [ %220, %405 ], [ %221, %398 ]
  br i1 %404, label %416, label %412

412:                                              ; preds = %407
  %413 = getelementptr inbounds %struct.off_runs, ptr %408, i64 0, i32 1
  %414 = load i64, ptr %413, align 8
  %415 = icmp eq i64 %414, 0
  br i1 %415, label %217, label %416

416:                                              ; preds = %412, %407
  %417 = phi i32 [ %403, %412 ], [ 0, %407 ]
  %418 = phi i32 [ 0, %412 ], [ %409, %407 ]
  %419 = phi i64 [ %414, %412 ], [ 0, %407 ]
  %420 = ashr exact i64 %232, 3
  %421 = icmp eq i32 %418, 0
  br i1 %421, label %422, label %491

422:                                              ; preds = %416, %201
  %423 = phi i64 [ %420, %416 ], [ %202, %201 ]
  %424 = phi i32 [ %417, %416 ], [ %203, %201 ]
  %425 = phi ptr [ %408, %416 ], [ %204, %201 ]
  %426 = phi i64 [ %419, %416 ], [ %206, %201 ]
  %427 = getelementptr inbounds %struct.off_runs, ptr %425, i64 0, i32 1
  store i64 0, ptr %427, align 8
  %428 = icmp sgt i64 %426, 2
  br i1 %428, label %429, label %439

429:                                              ; preds = %422, %429
  %430 = phi i64 [ %437, %429 ], [ %426, %422 ]
  %431 = phi ptr [ %434, %429 ], [ %425, %422 ]
  %432 = phi i32 [ %433, %429 ], [ %424, %422 ]
  %433 = add nsw i32 %432, 1
  %434 = getelementptr inbounds %struct.off_runs, ptr %431, i64 1
  store i64 %423, ptr %434, align 8
  %435 = lshr i64 %430, 1
  %436 = getelementptr inbounds %struct.off_runs, ptr %431, i64 1, i32 1
  store i64 %435, ptr %436, align 8
  %437 = sub nsw i64 %430, %435
  %438 = icmp sgt i64 %437, 2
  br i1 %438, label %429, label %439

439:                                              ; preds = %429, %422
  %440 = phi i32 [ %424, %422 ], [ %433, %429 ]
  %441 = phi ptr [ %425, %422 ], [ %434, %429 ]
  %442 = phi i64 [ %426, %422 ], [ %437, %429 ]
  %443 = and i32 %440, 1
  %444 = icmp eq i64 %442, 1
  br i1 %444, label %445, label %466

445:                                              ; preds = %439
  %446 = icmp eq i32 %443, 0
  br i1 %446, label %463, label %447

447:                                              ; preds = %445
  %448 = getelementptr ptr, ptr %9, i64 %423
  %449 = getelementptr inbounds ptr, ptr %34, i64 %423
  %450 = load ptr, ptr %449, align 8
  %451 = ptrtoint ptr %450 to i64
  %452 = add i64 %199, %451
  %453 = shl nsw i64 %423, 3
  %454 = add i64 %453, %200
  %455 = call i64 @llvm.umax.i64(i64 %452, i64 %454)
  %456 = sub i64 %198, %453
  %457 = add i64 %456, %455
  %458 = and i64 %457, -8
  %459 = add i64 %458, 8
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %449, ptr align 8 %448, i64 %459, i1 false)
  %460 = sub i64 %451, %197
  %461 = ashr exact i64 %460, 3
  %462 = getelementptr inbounds i8, ptr %9, i64 %460
  store ptr %462, ptr %448, align 8
  br label %491

463:                                              ; preds = %445
  %464 = icmp eq i32 %440, 0
  %465 = select i1 %464, i32 20, i32 0
  br label %491

466:                                              ; preds = %439
  %467 = add nsw i32 %440, 1
  %468 = getelementptr inbounds %struct.off_runs, ptr %441, i64 1
  store i64 %423, ptr %468, align 8
  %469 = getelementptr inbounds %struct.off_runs, ptr %441, i64 1, i32 1
  store i64 0, ptr %469, align 8
  %470 = icmp eq i32 %443, 0
  br i1 %470, label %471, label %491

471:                                              ; preds = %466
  %472 = getelementptr ptr, ptr %9, i64 %423
  %473 = getelementptr inbounds ptr, ptr %34, i64 %423
  %474 = load ptr, ptr %473, align 8
  %475 = load ptr, ptr %474, align 8
  %476 = ptrtoint ptr %475 to i64
  %477 = add i64 %199, %476
  %478 = shl nsw i64 %423, 3
  %479 = add i64 %478, %200
  %480 = call i64 @llvm.umax.i64(i64 %477, i64 %479)
  %481 = sub i64 %198, %478
  %482 = add i64 %481, %480
  %483 = and i64 %482, -8
  %484 = add i64 %483, 8
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %473, ptr align 8 %472, i64 %484, i1 false)
  %485 = sub i64 %476, %197
  %486 = ptrtoint ptr %474 to i64
  %487 = sub i64 %486, %197
  %488 = ashr exact i64 %487, 3
  %489 = getelementptr inbounds i8, ptr %9, i64 %487
  %490 = getelementptr inbounds i8, ptr %9, i64 %485
  store ptr %489, ptr %472, align 8
  store ptr %490, ptr %489, align 8
  br label %491

491:                                              ; preds = %471, %466, %463, %447, %416
  %492 = phi i64 [ %420, %416 ], [ %461, %447 ], [ %423, %466 ], [ %488, %471 ], [ %423, %463 ]
  %493 = phi i32 [ %417, %416 ], [ %440, %447 ], [ %467, %466 ], [ %467, %471 ], [ %440, %463 ]
  %494 = phi ptr [ %408, %416 ], [ %441, %447 ], [ %468, %466 ], [ %468, %471 ], [ %441, %463 ]
  %495 = phi i32 [ %418, %416 ], [ 0, %447 ], [ 0, %466 ], [ 0, %471 ], [ %465, %463 ]
  switch i32 %495, label %499 [
    i32 0, label %201
    i32 20, label %496
  ]

496:                                              ; preds = %491
  %497 = icmp eq ptr %34, %3
  br i1 %497, label %499, label %498

498:                                              ; preds = %496
  call void @free(ptr noundef %34) #12
  br label %499

499:                                              ; preds = %491, %25, %496, %498
  call void @llvm.lifetime.end.p0(i64 960, ptr nonnull %5) #12
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %4) #12
  call void @llvm.lifetime.end.p0(i64 1600, ptr nonnull %3) #12
  %500 = icmp sgt i64 %1, 0
  br i1 %500, label %501, label %508

501:                                              ; preds = %499, %501
  %502 = phi i64 [ %506, %501 ], [ 0, %499 ]
  %503 = getelementptr inbounds %struct.Slot, ptr %0, i64 %502
  %504 = getelementptr inbounds ptr, ptr %9, i64 %502
  %505 = load ptr, ptr %504, align 8
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %503, ptr noundef nonnull align 8 dereferenceable(16) %505, i64 16, i1 false)
  %506 = add nuw nsw i64 %502, 1
  %507 = icmp eq i64 %506, %1
  br i1 %507, label %508, label %501

508:                                              ; preds = %501, %499, %16
  %509 = phi i32 [ 1, %16 ], [ 0, %499 ], [ 0, %501 ]
  store ptr %12, ptr @msort_jb, align 8
  call void @free(ptr noundef %9) #12
  call void @free(ptr noundef %11) #12
  call void @llvm.lifetime.end.p0(i64 200, ptr nonnull %6) #12
  ret i32 %509
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #3

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite)

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #5

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #3

; Function Attrs: nounwind returns_twice
declare i32 @_setjmp(ptr noundef) local_unnamed_addr #6

; Function Attrs: mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite)
declare void @free(ptr allocptr nocapture noundef) local_unnamed_addr #7


; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #9

attributes #0 = { noreturn nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { noreturn nounwind "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #2 = { nounwind uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #3 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #4 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #5 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #6 = { nounwind returns_twice "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #7 = { mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite) "alloc-family"="malloc" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #8 = { "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #9 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #10 = { noreturn nounwind }
attributes #11 = { nounwind allocsize(0) }
attributes #12 = { nounwind }
attributes #13 = { nounwind returns_twice }


; t2_ghash(g) / t2_garray(g): the file\'s hash or array a global holds, made
; the first time any function reaches it.
define internal %Slot @t2_ghash(%Slot* %g) {
entry:
  %v = load %Slot, %Slot* %g
  %t = extractvalue %Slot %v, 0
  %has = icmp eq i8 %t, 5
  br i1 %has, label %done, label %make
make:
  %h = call %Slot @t2_hnew()
  store %Slot %h, %Slot* %g
  ret %Slot %h
done:
  ret %Slot %v
}
define internal %Array* @t2_garray(%Slot* %g) {
entry:
  %v = load %Slot, %Slot* %g
  %t = extractvalue %Slot %v, 0
  %has = icmp eq i8 %t, 6
  br i1 %has, label %done, label %make
make:
  %a = call %Array* @t2_new_array()
  %i = ptrtoint %Array* %a to i64
  %s = call %Slot @t2_slot(i8 6, i64 %i)
  store %Slot %s, %Slot* %g
  ret %Array* %a
done:
  %p = extractvalue %Slot %v, 1
  %r = inttoptr i64 %p to %Array*
  ret %Array* %r
}
; t2_arev(a) -> a new list of a\'s elements, last first.
define internal %Array* @t2_arev(%Array* %a) {
entry:
  %r = call %Array* @t2_new_array()
  %n = call i64 @t2_alen(%Array* %a)
  br label %loop
loop:
  %i = phi i64 [ %n, %entry ], [ %im, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %im = sub i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %im)
  call void @t2_apush(%Array* %r, %Slot %v)
  br label %loop
done:
  ret %Array* %r
}
; WHOLE ASSIGN IN PLACE (`@a = LIST`, `%h = LIST` on the container a tie or a
; reference names): the list copied first -- it may read the aggregate --
; then, for a tied one, perl\'s calls; for any other, cleared and refilled.
@lit_tm_extend = private unnamed_addr constant [7 x i8] c"EXTEND\00"
define internal void @t2_aassign(%Array* %a, %Array* %l) {
entry:
  %c = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %c, %Array* %l)
  %n = call i64 @t2_alen(%Array* %c)
  %m = call %Meta* @t2_meta(%Array* %a)
  %d0 = icmp eq %Meta* %m, @t2_meta_default
  %da = icmp eq %Meta* %m, @t2_meta_alias   ; (`@_ = LIST`: new cells, no tie)
  %d = or i1 %d0, %da
  br i1 %d, label %plain, label %tied
plain:
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 0, i64* %lp
  call void @t2_aappend(%Array* %a, %Array* %c)
  ret void
tied:
  %o = call %Slot @t2_tie_obj(%Array* %a)
  %ca = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %ca, %Slot %o)
  %cm = call %Str @t2_str(i8* getelementptr ([6 x i8], [6 x i8]* @lit_tm_clear, i64 0, i64 0), i64 5)
  %cr = call %Slot @t2_tie_call(%Array* %ca, %Str %cm)
  %xa = call %Array* @t2_new_array()
  call void @t2_apush(%Array* %xa, %Slot %o)
  %ns = call %Slot @t2_box_i64(i64 %n)
  call void @t2_apush(%Array* %xa, %Slot %ns)
  %xm = call %Str @t2_str(i8* getelementptr ([7 x i8], [7 x i8]* @lit_tm_extend, i64 0, i64 0), i64 6)
  %xr = call %Slot @t2_tie_call(%Array* %xa, %Str %xm)
  br label %loop
loop:
  %i = phi i64 [ 0, %tied ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %c, i64 %i)
  call void @t2_aset(%Array* %a, i64 %i, %Slot %v, i8* null, i64 0)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret void
}
define internal void @t2_hassign(%Slot %h, %Array* %l) {
entry:
  %c = call %Array* @t2_new_array()
  call void @t2_aappend(%Array* %c, %Array* %l)
  %a = call %Array* @t2_harr(%Slot %h)
  %m = call %Meta* @t2_meta(%Array* %a)
  %d0 = icmp eq %Meta* %m, @t2_meta_default
  %dh = icmp eq %Meta* %m, @t2_meta_hcells   ; (a hash of cells: new ones)
  %d = or i1 %d0, %dh
  br i1 %d, label %plain, label %tied
plain:
  ; (element 0 is the hash\'s class: kept)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  store i64 1, i64* %lp
  call void @t2_hfroma(%Slot %h, %Array* %c)
  ret void
tied:
  ; (a tie\'s hfroma is CLEAR, then STORE each pair)
  call void @t2_hfroma(%Slot %h, %Array* %c)
  ret void
}
; t2_mresolve(invocant, method, " at FILE line N.\n", start, mode) -> the method\'s code,
; looked up from (mode 0) the invocant\'s class, (1) start, a qualified name\'s
; package, or (2) start\'s @ISA, a SUPER:: call\'s; where perl dies (no class,
; no method), a die naming that class, and t2_nomethod\'s code.
define internal i8* @t2_mresolve(%Slot %inv, %Str %m, %Str %at, %Str %start, i8 %mode) {
entry:
  store %Str %at, %Str* @t2_call_at
  %t = extractvalue %Slot %inv, 0
  switch i8 %t, label %named [ i8 0, label %undef i8 5, label %ref i8 6, label %ref i8 7, label %unbl i8 8, label %ref i8 9, label %ref ]
undef:
  %u0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %u1 = call %Str @t2_concat(%Str %u0, %Str %m)
  %u2 = call %Str @t2_str(i8* getelementptr ([24 x i8], [24 x i8]* @lit_undefv, i64 0, i64 0), i64 23)
  %u3 = call %Str @t2_concat(%Str %u1, %Str %u2)
  br label %die
ref:
  %cl = call %Slot @t2_class_of(%Slot %inv)
  %ct = extractvalue %Slot %cl, 0
  %blessed = icmp eq i8 %ct, 3
  br i1 %blessed, label %obj, label %unbl
obj:
  %cn = call %Str @t2_slot_str(%Slot %cl)
  br label %look
unbl:
  %b0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %b1 = call %Str @t2_concat(%Str %b0, %Str %m)
  %b2 = call %Str @t2_str(i8* getelementptr ([25 x i8], [25 x i8]* @lit_unbl, i64 0, i64 0), i64 24)
  %b3 = call %Str @t2_concat(%Str %b1, %Str %b2)
  br label %die
named:
  %nn = call %Str @t2_slot_str(%Slot %inv)
  %nl = extractvalue %Str %nn, 1
  %empty = icmp eq i64 %nl, 0
  br i1 %empty, label %nopkg, label %look
nopkg:
  %p0 = call %Str @t2_str(i8* getelementptr ([20 x i8], [20 x i8]* @lit_cm, i64 0, i64 0), i64 19)
  %p1 = call %Str @t2_concat(%Str %p0, %Str %m)
  %p2 = call %Str @t2_str(i8* getelementptr ([40 x i8], [40 x i8]* @lit_nopkg, i64 0, i64 0), i64 39)
  %p3 = call %Str @t2_concat(%Str %p1, %Str %p2)
  br label %die
look:
  %own = phi %Str [ %cn, %obj ], [ %nn, %named ]
  %fromown = icmp eq i8 %mode, 0
  %c = select i1 %fromown, %Str %own, %Str %start
  %super = icmp eq i8 %mode, 2
  %r = call i8* @t2_mfind_u(%Str %c, %Str %m, i1 %super)
  %got = icmp ne i8* %r, null
  br i1 %got, label %ok, label %miss
ok:
  ret i8* %r
miss:
  %l0 = call %Str @t2_str(i8* getelementptr ([29 x i8], [29 x i8]* @lit_lom, i64 0, i64 0), i64 28)
  %l1 = call %Str @t2_concat(%Str %l0, %Str %m)
  %l2 = call %Str @t2_str(i8* getelementptr ([16 x i8], [16 x i8]* @lit_via, i64 0, i64 0), i64 15)
  %l3 = call %Str @t2_concat(%Str %l1, %Str %l2)
  %l4 = call %Str @t2_concat(%Str %l3, %Str %c)
  %tb = call %Slot @t2_stash_table()
  %s = call %Slot @t2_hget(%Slot %tb, %Str %c)
  %st = extractvalue %Slot %s, 0
  %known = icmp eq i8 %st, 5
  br i1 %known, label %quote, label %forgot
quote:
  %k0 = call %Str @t2_str(i8* getelementptr ([2 x i8], [2 x i8]* @lit_q, i64 0, i64 0), i64 1)
  %k1 = call %Str @t2_concat(%Str %l4, %Str %k0)
  br label %die
forgot:
  %f0 = call %Str @t2_str(i8* getelementptr ([32 x i8], [32 x i8]* @lit_forgot, i64 0, i64 0), i64 31)
  %f1 = call %Str @t2_concat(%Str %l4, %Str %f0)
  %f2 = call %Str @t2_concat(%Str %f1, %Str %c)
  %f3 = call %Str @t2_str(i8* getelementptr ([4 x i8], [4 x i8]* @lit_qp, i64 0, i64 0), i64 3)
  %f4 = call %Str @t2_concat(%Str %f2, %Str %f3)
  br label %die
die:
  %msg = phi %Str [ %u3, %undef ], [ %b3, %unbl ], [ %p3, %nopkg ], [ %k1, %quote ], [ %f4, %forgot ]
  %full = call %Str @t2_concat(%Str %msg, %Str %at)
  call void @t2_die_unwind(%Str %full)
  ret i8* bitcast (%Slot (%Array*)* @t2_nomethod to i8*)
}
; t2_nomethod(@_) -> undef: called where no method was found, a die already set.
define internal %Slot @t2_nomethod(%Array* %args) {
entry:
  ret %Slot zeroinitializer
}
define internal %Slot @t2_hget_d(%Slot %h, %Str %k) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %undef, label %get
get:
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %j)
  ret %Slot %v
undef:
  ret %Slot zeroinitializer
}
define internal i1 @t2_hexists_d(%Slot %h, %Str %k) {
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %e = icmp sge i64 %i, 0
  ret i1 %e
}
; t2_hdelete(h, k) -> k\'s value (undef if none), its pair taken out.
define internal %Slot @t2_hdelete_d(%Slot %h, %Str %k) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %none, label %take
none:
  ret %Slot zeroinitializer
take:
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %a, i64 %j)
  %lp = getelementptr %Array, %Array* %a, i32 0, i32 0
  %n = load i64, i64* %lp
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  br label %loop
loop:
  %d = phi i64 [ %i, %take ], [ %d2, %move ]
  %src = add i64 %d, 2
  %more = icmp slt i64 %src, %n
  br i1 %more, label %move, label %done
move:
  %sp = getelementptr %Slot, %Slot* %els, i64 %src
  %sv = load %Slot, %Slot* %sp
  %dp = getelementptr %Slot, %Slot* %els, i64 %d
  store %Slot %sv, %Slot* %dp
  %d2 = add i64 %d, 1
  br label %loop
done:
  %n2 = sub i64 %n, 2
  store i64 %n2, i64* %lp
  ret %Slot %v
}
define internal void @t2_hfroma_d(%Slot %h, %Array* %l) {
entry:
  %n = call i64 @t2_alen(%Array* %l)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ks = call %Slot @t2_aget(%Array* %l, i64 %i)
  %k = call %Str @t2_slot_str(%Slot %ks)
  %j = add i64 %i, 1
  %v = call %Slot @t2_aget(%Array* %l, i64 %j)
  call void @t2_hset(%Slot %h, %Str %k, %Slot %v)
  %i2 = add i64 %i, 2
  br label %loop
done:
  ret void
}
define internal i64 @t2_hcount_d(%Slot %h) {
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %p = sub i64 %n, 1
  %c = sdiv i64 %p, 2
  ret i64 %c
}
; t2_hpick(h, from) -> every other element of the hash\'s pairs from index
; from: 1 its keys, 2 its values.
define internal %Array* @t2_hpick(%Slot %h, i64 %from) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ %from, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 2
  br label %loop
done:
  ret %Array* %r
}
; t2_aslice(a, ix) -> a new list of a\'s elements at the indices ix holds, in
; their order: from the end where negative, undef outside the array -- perl\'s
; aslice read (it makes no element).
define internal %Array* @t2_aslice(%Array* %a, %Array* %ix) {
entry:
  %n = call i64 @t2_alen(%Array* %ix)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k2, %body ]
  %more = icmp slt i64 %k, %n
  br i1 %more, label %body, label %done
body:
  %is = call %Slot @t2_aget(%Array* %ix, i64 %k)
  %i = call i64 @t2_slot_i64(%Slot %is)
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %k2 = add i64 %k, 1
  br label %loop
done:
  ret %Array* %r
}
; t2_unpack_c(s, n) -> unpack "C<n>" of s: its first n bytes (every byte
; where n < 0, "C*"), each a number.
define internal %Array* @t2_unpack_c(%Str %s, i64 %n) {
entry:
  %p = extractvalue %Str %s, 0
  %len = extractvalue %Str %s, 1
  %all = icmp slt i64 %n, 0
  %short = icmp slt i64 %len, %n
  %uselen = or i1 %all, %short
  %m = select i1 %uselen, i64 %len, i64 %n
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %m
  br i1 %more, label %body, label %done
body:
  %bp = getelementptr i8, i8* %p, i64 %i
  %byte = load i8, i8* %bp
  %b = zext i8 %byte to i64
  %v = call %Slot @t2_box_i64(i64 %b)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
; t2_glob(pat) -> glob PAT in a list: the files it matches, through libc
; glob(3) with File::Glob\'s flags (NOSORT 4 | BRACE 1024 | NOMAGIC 2048 |
; TILDE 4096: the pattern itself where it has no metacharacters), sorted as
; perl sorts them (case aside, then bytes). A brace\'s alternatives perl
; keeps in their order, each sorted: not this sort -- a stop. glob_t\'s gl_pathc at 0, gl_pathv
; at 8 (x86-64), its 72 bytes allocated as 128. A pattern with whitespace is
; several patterns to perl: a stop too.
declare i32 @glob(i8*, i32, i8*, i8*)
declare i8* @calloc(i64, i64)
declare void @qsort(i8*, i64, i64, i32 (i8*, i8*)*)
declare i32 @strcasecmp(i8*, i8*)
declare i32 @strcmp(i8*, i8*)
@msg_globws = private unnamed_addr constant [76 x i8] c"chalk: refused at run time: a glob pattern with whitespace or a brace (T2)\0A\00"
define internal i32 @t2_glob_cmp(i8* %a, i8* %b) {
entry:
  %pa = bitcast i8* %a to i8**
  %sa = load i8*, i8** %pa
  %pb = bitcast i8* %b to i8**
  %sb = load i8*, i8** %pb
  %c = call i32 @strcasecmp(i8* %sa, i8* %sb)
  %z = icmp eq i32 %c, 0
  br i1 %z, label %tie, label %out
tie:
  %d = call i32 @strcmp(i8* %sa, i8* %sb)
  ret i32 %d
out:
  ret i32 %c
}
define internal %Array* @t2_glob(%Str %pat) {
entry:
  %p = extractvalue %Str %pat, 0
  %l = extractvalue %Str %pat, 1
  br label %scan
scan:
  %j = phi i64 [ 0, %entry ], [ %j2, %next ]
  %more = icmp slt i64 %j, %l
  br i1 %more, label %look, label %go
look:
  %cp = getelementptr i8, i8* %p, i64 %j
  %ch = load i8, i8* %cp
  %sp = icmp eq i8 %ch, 32
  %tb = icmp eq i8 %ch, 9
  %nl = icmp eq i8 %ch, 10
  %br = icmp eq i8 %ch, 123
  %w1 = or i1 %sp, %tb
  %w2 = or i1 %w1, %nl
  %w = or i1 %w2, %br
  br i1 %w, label %ws, label %next
next:
  %j2 = add i64 %j, 1
  br label %scan
ws:
  call void @t2_stop(i8* getelementptr ([76 x i8], [76 x i8]* @msg_globws, i64 0, i64 0), i64 75)
  unreachable
go:
  %sz = add i64 %l, 1
  %z = call i8* @malloc(i64 %sz)
  call i8* @memcpy(i8* %z, i8* %p, i64 %l)
  %end = getelementptr i8, i8* %z, i64 %l
  store i8 0, i8* %end
  %r = call %Array* @t2_new_array()
  %g = call i8* @calloc(i64 1, i64 128)
  %rc = call i32 @glob(i8* %z, i32 7172, i8* null, i8* %g)
  %ok = icmp eq i32 %rc, 0
  br i1 %ok, label %got, label %done
got:
  %pcp = bitcast i8* %g to i64*
  %n = load i64, i64* %pcp
  %pvp0 = getelementptr i8, i8* %g, i64 8
  %pvp = bitcast i8* %pvp0 to i8***
  %pv = load i8**, i8*** %pvp
  %pv8 = bitcast i8** %pv to i8*
  call void @qsort(i8* %pv8, i64 %n, i64 8, i32 (i8*, i8*)* @t2_glob_cmp)
  br label %loop
loop:
  %i = phi i64 [ 0, %got ], [ %i1, %push ]
  %again = icmp slt i64 %i, %n
  br i1 %again, label %push, label %done
push:
  %ps = getelementptr i8*, i8** %pv, i64 %i
  %s = load i8*, i8** %ps
  %len = call i64 @strlen(i8* %s)
  %str = call %Str @t2_str(i8* %s, i64 %len)
  %v = call %Slot @t2_box_str(%Str %str)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
; t2_qx(cmd) -> qx`CMD` / readpipe in scalar context: the command run by
; libc popen, all it printed read back. T2\'s prints are write(2)s, never
; buffered, so nothing waits to be flushed before the fork. Its exit status
; ($?) is not kept.
declare i8* @popen(i8*, i8*)
declare i32 @pclose(i8*)
declare i64 @fread(i8*, i64, i64, i8*)
@lit_popen_r = private unnamed_addr constant [2 x i8] c"r\00"
define internal %Str @t2_qx(%Str %cmd) {
entry:
  %p = extractvalue %Str %cmd, 0
  %l = extractvalue %Str %cmd, 1
  %sz = add i64 %l, 1
  %z = call i8* @malloc(i64 %sz)
  call i8* @memcpy(i8* %z, i8* %p, i64 %l)
  %end = getelementptr i8, i8* %z, i64 %l
  store i8 0, i8* %end
  %f = call i8* @popen(i8* %z, i8* getelementptr ([2 x i8], [2 x i8]* @lit_popen_r, i64 0, i64 0))
  %none = icmp eq i8* %f, null
  %b0 = call i8* @malloc(i64 4096)
  br i1 %none, label %out, label %read
read:
  %buf = phi i8* [ %b0, %entry ], [ %buf2, %grown ]
  %len = phi i64 [ 0, %entry ], [ %len2, %grown ]
  %cap = phi i64 [ 4096, %entry ], [ %cap2, %grown ]
  %at = getelementptr i8, i8* %buf, i64 %len
  %room = sub i64 %cap, %len
  %n = call i64 @fread(i8* %at, i64 1, i64 %room, i8* %f)
  %len2 = add i64 %len, %n
  %eof = icmp eq i64 %n, 0
  br i1 %eof, label %close, label %grow
grow:
  %full = icmp eq i64 %len2, %cap
  %capd = mul i64 %cap, 2
  %cap2 = select i1 %full, i64 %capd, i64 %cap
  %buf2 = call i8* @realloc(i8* %buf, i64 %cap2)
  br label %grown
grown:
  br label %read
close:
  %rc = call i32 @pclose(i8* %f)
  br label %out
out:
  %ob = phi i8* [ %b0, %entry ], [ %buf, %close ]
  %ol = phi i64 [ 0, %entry ], [ %len2, %close ]
  %s = call %Str @t2_str(i8* %ob, i64 %ol)
  ret %Str %s
}
; t2_localtime_tm(t, now) -> libc\'s localtime_r of t (of time(NULL) where
; now): a struct tm, its first nine ints perl\'s nine fields in order.
declare i64 @time(i64*)
declare i8* @localtime_r(i64*, i8*)
declare i64 @strftime(i8*, i64, i8*, i8*)
@fmt_ctime = private unnamed_addr constant [21 x i8] c"%a %b %e %H:%M:%S %Y\00"
define internal i8* @t2_localtime_tm(i64 %t, i1 %now) {
entry:
  %tp = call i8* @malloc(i64 8)
  %tq = bitcast i8* %tp to i64*
  br i1 %now, label %clock, label %given
clock:
  %c = call i64 @time(i64* null)
  br label %have
given:
  br label %have
have:
  %v = phi i64 [ %c, %clock ], [ %t, %given ]
  store i64 %v, i64* %tq
  %tm = call i8* @malloc(i64 128)
  %u = call i8* @localtime_r(i64* %tq, i8* %tm)
  ret i8* %tm
}
; t2_localtime_list(t, now) -> localtime in a list: (sec, min, hour, mday,
; mon, year, wday, yday, isdst).
define internal %Array* @t2_localtime_list(i64 %t, i1 %now) {
entry:
  %tm = call i8* @t2_localtime_tm(i64 %t, i1 %now)
  %f = bitcast i8* %tm to i32*
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, 9
  br i1 %more, label %body, label %done
body:
  %fp = getelementptr i32, i32* %f, i64 %i
  %x = load i32, i32* %fp
  %x64 = sext i32 %x to i64
  %s = call %Slot @t2_box_i64(i64 %x64)
  call void @t2_apush(%Array* %r, %Slot %s)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
; t2_localtime_str(t, now) -> localtime in scalar context: ctime(3)\'s text
; without its newline, "Thu Sep  9 01:46:40 1999".
define internal %Str @t2_localtime_str(i64 %t, i1 %now) {
entry:
  %tm = call i8* @t2_localtime_tm(i64 %t, i1 %now)
  %buf = call i8* @malloc(i64 64)
  %n = call i64 @strftime(i8* %buf, i64 64, i8* getelementptr ([21 x i8], [21 x i8]* @fmt_ctime, i64 0, i64 0), i8* %tm)
  %s = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %s
}
; t2_range(lo, hi) -> a new list of the integers lo to hi (none when hi < lo):
; perl\'s range of numbers.
define internal %Array* @t2_range(i64 %lo, i64 %hi) {
entry:
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ %lo, %entry ], [ %i2, %body ]
  %more = icmp sle i64 %i, %hi
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_box_i64(i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  ; (the last at IV_MAX: one past it is no IV)
  %last = icmp eq i64 %i, %hi
  %i2 = add i64 %i, 1
  br i1 %last, label %done, label %loop
done:
  ret %Array* %r
}
; ---- PERL\'S RANGE OF TWO SCALARS (pp_flop). On numbers where a bound
; holds one, is defined and no string, or where the left looks like a number
; (not starting "0") or is undef while the right is defined -- and the right
; is undef or looks like one; else on strings: the left, magic-incremented,
; while no longer than the right, up to the right.
@msg_range_unsure = private unnamed_addr constant [74 x i8] c"a range whose bound may be Inf, NaN or \220 but true\22: stopped (chalk, T2)\0A\00"
@msg_range_big = private unnamed_addr constant [59 x i8] c"Range iterator outside integer range: stopped (chalk, T2)\0A\00"
define internal i8 @t2_byte_at(i8* %p, i64 %n, i64 %i) {
entry:
  %in = icmp slt i64 %i, %n
  br i1 %in, label %rd, label %out
rd:
  %q = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %q
  ret i8 %c
out:
  ret i8 0
}
define internal i1 @t2_is_space_c(i8 %c) {
  %sp = icmp eq i8 %c, 32
  %g = icmp uge i8 %c, 9
  %l = icmp ule i8 %c, 13
  %ws = and i1 %g, %l
  %r = or i1 %sp, %ws
  ret i1 %r
}
define internal i1 @t2_is_digit_c(i8 %c) {
  %g = icmp uge i8 %c, 48
  %l = icmp ule i8 %c, 57
  %r = and i1 %g, %l
  ret i1 %r
}
; (the first index at or after i whose byte is not a space; not a digit)
define internal i64 @t2_skip_space(i8* %p, i64 %n, i64 %i0) {
entry:
  br label %loop
loop:
  %i = phi i64 [ %i0, %entry ], [ %i1, %next ]
  %in = icmp slt i64 %i, %n
  br i1 %in, label %test, label %done
test:
  %c = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i)
  %y = call i1 @t2_is_space_c(i8 %c)
  br i1 %y, label %next, label %done
next:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %i
}
define internal i64 @t2_skip_digits(i8* %p, i64 %n, i64 %i0) {
entry:
  br label %loop
loop:
  %i = phi i64 [ %i0, %entry ], [ %i1, %next ]
  %in = icmp slt i64 %i, %n
  br i1 %in, label %test, label %done
test:
  %c = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i)
  %y = call i1 @t2_is_digit_c(i8 %c)
  br i1 %y, label %next, label %done
next:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %i
}
; t2_lln(s) -> 1 where perl\'s looks_like_number says s is a number (spaces,
; a sign, digits with a point or a point and digits, an exponent, spaces),
; 0 where it is not -- 2 where T2 does not tell: an Inf or a NaN, "0 but true".
@lit_0bt = private unnamed_addr constant [11 x i8] c"0 but true\00"
define internal i8 @t2_lln(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %ten = icmp eq i64 %n, 10
  br i1 %ten, label %cmp0bt, label %go
cmp0bt:
  %mc = call i32 @memcmp(i8* %p, i8* getelementptr ([11 x i8], [11 x i8]* @lit_0bt, i64 0, i64 0), i64 10)
  %is0bt = icmp eq i32 %mc, 0
  br i1 %is0bt, label %unsure, label %go
go:
  %i0 = call i64 @t2_skip_space(i8* %p, i64 %n, i64 0)
  %c0 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i0)
  %plus = icmp eq i8 %c0, 43
  %minus = icmp eq i8 %c0, 45
  %sg = or i1 %plus, %minus
  %i0s = add i64 %i0, 1
  %i1 = select i1 %sg, i64 %i0s, i64 %i0
  %c1 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i1)
  %lc = or i8 %c1, 32
  %isi = icmp eq i8 %lc, 105
  %isn = icmp eq i8 %lc, 110
  %inan = or i1 %isi, %isn
  br i1 %inan, label %unsure, label %mant
mant:
  %i2 = call i64 @t2_skip_digits(i8* %p, i64 %n, i64 %i1)
  %nd1 = sub i64 %i2, %i1
  %c2 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i2)
  %dot = icmp eq i8 %c2, 46
  %i2d = add i64 %i2, 1
  %i3 = call i64 @t2_skip_digits(i8* %p, i64 %n, i64 %i2d)
  %nd2 = sub i64 %i3, %i2d
  %i3f = select i1 %dot, i64 %i3, i64 %i2
  %nd2f = select i1 %dot, i64 %nd2, i64 0
  %tot = add i64 %nd1, %nd2f
  %hasd = icmp sgt i64 %tot, 0
  br i1 %hasd, label %exp, label %no
exp:
  %c3 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i3f)
  %le = or i8 %c3, 32
  %ise = icmp eq i8 %le, 101
  %j0 = add i64 %i3f, 1
  %c4 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %j0)
  %ep = icmp eq i8 %c4, 43
  %em = icmp eq i8 %c4, 45
  %esg = or i1 %ep, %em
  %j0s = add i64 %j0, 1
  %j1 = select i1 %esg, i64 %j0s, i64 %j0
  %j2 = call i64 @t2_skip_digits(i8* %p, i64 %n, i64 %j1)
  %ed = icmp sgt i64 %j2, %j1
  %expok = and i1 %ise, %ed
  %i4 = select i1 %expok, i64 %j2, i64 %i3f
  %i5 = call i64 @t2_skip_space(i8* %p, i64 %n, i64 %i4)
  %end = icmp eq i64 %i5, %n
  %r = select i1 %end, i8 1, i8 0
  ret i8 %r
no:
  ret i8 0
unsure:
  ret i8 2
}
; t2_streq_c(a, b) -> C\'s strcmp(a, b) == 0: equal up to a NUL in both (perl\'s
; strEQ, as pp_flop asks it).
define internal i1 @t2_streq_c(%Str %a, %Str %b) {
entry:
  %ap = extractvalue %Str %a, 0
  %an = extractvalue %Str %a, 1
  %bp = extractvalue %Str %b, 0
  %bn = extractvalue %Str %b, 1
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %ca = call i8 @t2_byte_at(i8* %ap, i64 %an, i64 %i)
  %cb = call i8 @t2_byte_at(i8* %bp, i64 %bn, i64 %i)
  %same = icmp eq i8 %ca, %cb
  br i1 %same, label %more, label %ne
more:
  %nul = icmp eq i8 %ca, 0
  br i1 %nul, label %eq, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
eq:
  ret i1 1
ne:
  ret i1 0
}
define internal %Array* @t2_range_slots(%Slot %l, %Slot %r) {
entry:
  %tl = extractvalue %Slot %l, 0
  %tr = extractvalue %Slot %r, 0
  %okl = icmp ne i8 %tl, 0
  %okr = icmp ne i8 %tr, 0
  %pokl = icmp eq i8 %tl, 3
  %pokr = icmp eq i8 %tr, 3
  %npl = xor i1 %pokl, true
  %npr = xor i1 %pokr, true
  ; (a number, or defined and no string: a reference too)
  %onl = and i1 %okl, %npl
  %onr = and i1 %okr, %npr
  %c1 = or i1 %onl, %onr
  br i1 %c1, label %num, label %strs
strs:
  %ls = call %Str @t2_slot_str(%Slot %l)
  %rs = call %Str @t2_slot_str(%Slot %r)
  %lnl0 = call i8 @t2_lln(%Str %ls)
  %lnr0 = call i8 @t2_lln(%Str %rs)
  %lnl = select i1 %pokl, i8 %lnl0, i8 0
  %lnr = select i1 %pokr, i8 %lnr0, i8 0
  %ul = icmp eq i8 %lnl, 2
  %ur = icmp eq i8 %lnr, 2
  %un = or i1 %ul, %ur
  br i1 %un, label %unsure, label %decide
unsure:
  call void @t2_stop(i8* getelementptr ([74 x i8], [74 x i8]* @msg_range_unsure, i64 0, i64 0), i64 73)
  unreachable
decide:
  %lp = extractvalue %Str %ls, 0
  %ln = extractvalue %Str %ls, 1
  %f = call i8 @t2_byte_at(i8* %lp, i64 %ln, i64 0)
  %f0 = icmp eq i8 %f, 48
  %nf0 = xor i1 %f0, true
  %nokl = xor i1 %okl, true
  %a = and i1 %nokl, %okr
  %lyes = icmp eq i8 %lnl, 1
  %b0 = and i1 %lyes, %pokl
  %b = and i1 %b0, %nf0
  %ab = or i1 %a, %b
  %nokr = xor i1 %okr, true
  %ryes = icmp eq i8 %lnr, 1
  %c = or i1 %nokr, %ryes
  %n3 = and i1 %ab, %c
  br i1 %n3, label %num, label %str
num:
  ; (perl dies where a bound is past what an IV holds)
  %dl = call double @t2_slot_num(%Slot %l)
  %dr = call double @t2_slot_num(%Slot %r)
  %lo = fcmp olt double %dl, 0xC3E0000000000000
  %hi = fcmp ogt double %dr, 0x43E0000000000000
  %lo2 = and i1 %lo, %okl
  %hi2 = and i1 %hi, %okr
  ; (and a right bound that is a UV: past IV_MAX, pp_flop\'s die)
  %ruv = icmp eq i8 %tr, 4
  %hi3 = or i1 %hi2, %ruv
  %big = or i1 %lo2, %hi3
  br i1 %big, label %toobig, label %ints
toobig:
  call void @t2_stop(i8* getelementptr ([59 x i8], [59 x i8]* @msg_range_big, i64 0, i64 0), i64 58)
  unreachable
ints:
  %il = call i64 @t2_slot_i64(%Slot %l)
  %ir = call i64 @t2_slot_i64(%Slot %r)
  %ra = call %Array* @t2_range(i64 %il, i64 %ir)
  ret %Array* %ra
str:
  %out = call %Array* @t2_new_array()
  %len = extractvalue %Str %rs, 1
  br label %sloop
sloop:
  %s = phi %Str [ %ls, %str ], [ %s2, %inc ]
  %sn = extractvalue %Str %s, 1
  %fits = icmp sle i64 %sn, %len
  br i1 %fits, label %spush, label %sdone
spush:
  %sv = call %Slot @t2_box_str(%Str %s)
  call void @t2_apush(%Array* %out, %Slot %sv)
  %at = call i1 @t2_streq_c(%Str %s, %Str %rs)
  br i1 %at, label %sdone, label %smagic
smagic:
  ; (an empty string, or one no magic increment takes, goes to a number: the end)
  %empty = icmp eq i64 %sn, 0
  %ism = call i1 @t2_is_magic(%Str %s)
  %nm = xor i1 %ism, true
  %stop = or i1 %empty, %nm
  br i1 %stop, label %sdone, label %inc
inc:
  %s2 = call %Str @t2_str_magic_inc(%Str %s)
  br label %sloop
sdone:
  ret %Array* %out
}
; t2_hslice(h, keys) -> a new list of h\'s values at the keys, in their order,
; undef for a missing one -- perl\'s hslice read.
define internal %Array* @t2_hslice(%Slot %h, %Array* %keys) {
entry:
  %n = call i64 @t2_alen(%Array* %keys)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k2, %body ]
  %more = icmp slt i64 %k, %n
  br i1 %more, label %body, label %done
body:
  %ks = call %Slot @t2_aget(%Array* %keys, i64 %k)
  %key = call %Str @t2_slot_str(%Slot %ks)
  %v = call %Slot @t2_hget(%Slot %h, %Str %key)
  call void @t2_apush(%Array* %r, %Slot %v)
  %k2 = add i64 %k, 1
  br label %loop
done:
  ret %Array* %r
}
define internal %Array* @t2_hpairs_d(%Slot %h) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %n = call i64 @t2_alen(%Array* %a)
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %v = call %Slot @t2_aget(%Array* %a, i64 %i)
  call void @t2_apush(%Array* %r, %Slot %v)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
define internal %Array* @t2_hkeys_d(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 1)
  ret %Array* %r
}
define internal %Array* @t2_hvalues_d(%Slot %h) {
  %r = call %Array* @t2_hpick(%Slot %h, i64 2)
  ret %Array* %r
}
define internal void @t2_hset_d(%Slot %h, %Str %k, %Slot %v) {
entry:
  %a = call %Array* @t2_harr(%Slot %h)
  %i = call i64 @t2_hfind(%Array* %a, %Str %k)
  %miss = icmp slt i64 %i, 0
  br i1 %miss, label %add, label %put
add:
  %ks = call %Slot @t2_box_str(%Str %k)
  call void @t2_apush(%Array* %a, %Slot %ks)
  call void @t2_apush(%Array* %a, %Slot %v)
  ret void
put:
  %j = add i64 %i, 1
  %ep = getelementptr %Array, %Array* %a, i32 0, i32 2
  %els = load %Slot*, %Slot** %ep
  %p = getelementptr %Slot, %Slot* %els, i64 %j
  store %Slot %v, %Slot* %p
  ret void
}
; ---- builtins of one value: chr, ord, time, reverse of a string, x, -e, sprintf ----
@msg_chr = private unnamed_addr constant [56 x i8] c"chr of other than a byte (0..255): stopped (chalk, T2)\0A\00"
; chr(n): the string of one byte n. Past a byte perl\'s is a character: stopped.
define internal %Str @t2_chr(%Slot %v) {
entry:
  %n = call i64 @t2_slot_i64(%Slot %v)
  %lo = icmp slt i64 %n, 0
  %hi = icmp sgt i64 %n, 255
  %bad = or i1 %lo, %hi
  br i1 %bad, label %stop, label %ok
stop:
  call void @t2_stop(i8* getelementptr ([56 x i8], [56 x i8]* @msg_chr, i64 0, i64 0), i64 55)
  unreachable
ok:
  %buf = call i8* @malloc(i64 2)
  %c = trunc i64 %n to i8
  store i8 %c, i8* %buf
  %e = getelementptr i8, i8* %buf, i64 1
  store i8 0, i8* %e
  %r = call %Str @t2_str(i8* %buf, i64 1)
  ret %Str %r
}
; pack\'s C of v: its byte, wrapped to 0..255 as pack wraps it (-1 is 255).
define internal %Str @t2_pack_c(%Slot %v) {
  %n = call i64 @t2_bit_uv(%Slot %v)
  %b = and i64 %n, 255
  %bs = call %Slot @t2_box_i64(i64 %b)
  %r = call %Str @t2_chr(%Slot %bs)
  ret %Str %r
}
; ord(s): its first byte, 0 for "".
define internal i64 @t2_ord(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %z = icmp eq i64 %n, 0
  br i1 %z, label %none, label %some
none:
  ret i64 0
some:
  %c = load i8, i8* %p
  %r = zext i8 %c to i64
  ret i64 %r
}
; (time(3) is declared with t2_localtime_tm\'s)
define internal i64 @t2_time() {
  %t = call i64 @time(i64* null)
  ret i64 %t
}
; reverse in scalar context: the string\'s bytes, last first.
define internal %Str @t2_strrev(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  %e = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %e
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %src = getelementptr i8, i8* %p, i64 %i
  %c = load i8, i8* %src
  %j0 = sub i64 %n, %i
  %j = sub i64 %j0, 1
  %dst = getelementptr i8, i8* %buf, i64 %j
  store i8 %c, i8* %dst
  %i2 = add i64 %i, 1
  br label %loop
done:
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
; s x n: n copies of s ("" for n < 1).
define internal %Str @t2_repeat(%Str %s, i64 %k) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %neg = icmp slt i64 %k, 0
  %k1 = select i1 %neg, i64 0, i64 %k
  %tot = mul i64 %n, %k1
  %t1 = add i64 %tot, 1
  %buf = call i8* @malloc(i64 %t1)
  %e = getelementptr i8, i8* %buf, i64 %tot
  store i8 0, i8* %e
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %k1
  br i1 %more, label %body, label %done
body:
  %off = mul i64 %i, %n
  %dst = getelementptr i8, i8* %buf, i64 %off
  call i8* @memcpy(i8* %dst, i8* %p, i64 %n)
  %i2 = add i64 %i, 1
  br label %loop
done:
  %r = call %Str @t2_str(i8* %buf, i64 %tot)
  ret %Str %r
}
; (LIST) x n: a new list of n copies of the list\'s elements.
define internal %Array* @t2_arepeat(%Array* %a, i64 %k) {
entry:
  %r = call %Array* @t2_new_array()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %more = icmp slt i64 %i, %k
  br i1 %more, label %body, label %done
body:
  call void @t2_aappend(%Array* %r, %Array* %a)
  %i2 = add i64 %i, 1
  br label %loop
done:
  ret %Array* %r
}
; -e PATH: 1 where something is there, else undef.
define internal %Slot @t2_ftis(%Str %s) {
entry:
  %c = call i8* @t2_cstr(%Str %s)
  %a = call i32 @access(i8* %c, i32 0)
  %there = icmp eq i32 %a, 0
  br i1 %there, label %yes, label %no
yes:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
no:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
}
; t2_fmt(spec, kind, width, precision, v): one conversion of sprintf, by C\'s
; snprintf: spec is "%<flags>*.*<conv>" (kind 0 an integer, 1 a number, 2 a
; string) or "%<flags>*c" (kind 3, a character).
define internal %Str @t2_fmt(%Str %spec, i64 %kind, i64 %w, i64 %p, %Slot %v) {
entry:
  %sp = call i8* @t2_cstr(%Str %spec)
  %w32 = trunc i64 %w to i32
  %p32 = trunc i64 %p to i32
  switch i64 %kind, label %int [ i64 1, label %num
                                  i64 2, label %str
                                  i64 3, label %chr ]
int:
  %i = call i64 @t2_slot_i64(%Slot %v)
  %ni = call i32 (i8*, i64, i8*, ...) @snprintf(i8* null, i64 0, i8* %sp, i32 %w32, i32 %p32, i64 %i)
  %ni64 = sext i32 %ni to i64
  %ni1 = add i64 %ni64, 1
  %bi = call i8* @malloc(i64 %ni1)
  %xi = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %bi, i64 %ni1, i8* %sp, i32 %w32, i32 %p32, i64 %i)
  %ri = call %Str @t2_str(i8* %bi, i64 %ni64)
  ret %Str %ri
num:
  %d = call double @t2_slot_num(%Slot %v)
  %nd = call i32 (i8*, i64, i8*, ...) @snprintf(i8* null, i64 0, i8* %sp, i32 %w32, i32 %p32, double %d)
  %nd64 = sext i32 %nd to i64
  %nd1 = add i64 %nd64, 1
  %bd = call i8* @malloc(i64 %nd1)
  %xd = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %bd, i64 %nd1, i8* %sp, i32 %w32, i32 %p32, double %d)
  %rd = call %Str @t2_str(i8* %bd, i64 %nd64)
  ret %Str %rd
str:
  %s = call %Str @t2_slot_str(%Slot %v)
  %cs = call i8* @t2_cstr(%Str %s)
  %ns = call i32 (i8*, i64, i8*, ...) @snprintf(i8* null, i64 0, i8* %sp, i32 %w32, i32 %p32, i8* %cs)
  %ns64 = sext i32 %ns to i64
  %ns1 = add i64 %ns64, 1
  %bs = call i8* @malloc(i64 %ns1)
  %xs = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %bs, i64 %ns1, i8* %sp, i32 %w32, i32 %p32, i8* %cs)
  %rs = call %Str @t2_str(i8* %bs, i64 %ns64)
  ret %Str %rs
chr:
  %ci = call i64 @t2_slot_i64(%Slot %v)
  %c32 = trunc i64 %ci to i32
  %nc = call i32 (i8*, i64, i8*, ...) @snprintf(i8* null, i64 0, i8* %sp, i32 %w32, i32 %c32)
  %nc64 = sext i32 %nc to i64
  %nc1 = add i64 %nc64, 1
  %bc = call i8* @malloc(i64 %nc1)
  %xc = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %bc, i64 %nc1, i8* %sp, i32 %w32, i32 %c32)
  %rc = call %Str @t2_str(i8* %bc, i64 %nc64)
  ret %Str %rc
}
; t2_pow(l, r): perl\'s ** (pp_pow). Two integers (as perl reads them), the
; power not below 0: a base a power of 2 is a number, as pow() gives; one
; whose result surely fits 64 bits (its bits times the power at most 64) an
; integer by multiplying -- a UV past IV_MAX, a negative one past IV_MIN an
; NV. Anything else pow()\'s number.
declare double @llvm.pow.f64(double, double)
declare i64 @llvm.ctlz.i64(i64, i1)
define internal %Slot @t2_pow(%Slot %l0, %Slot %r0) {
entry:
  %r = call %Slot @t2_arith_num(%Slot %r0)
  %l = call %Slot @t2_arith_num(%Slot %l0)
  %rt = extractvalue %Slot %r, 0
  %lt = extractvalue %Slot %l, 0
  %rn = icmp eq i8 %rt, 2
  %ln = icmp eq i8 %lt, 2
  %either = or i1 %rn, %ln
  br i1 %either, label %float, label %ints
ints:
  %p = extractvalue %Slot %r, 1
  %b = extractvalue %Slot %l, 1
  %ruv = icmp eq i8 %rt, 4
  %luv = icmp eq i8 %lt, 4
  %pneg0 = icmp slt i64 %p, 0
  %rnotuv = xor i1 %ruv, true
  %pneg = and i1 %pneg0, %rnotuv
  %bneg0 = icmp slt i64 %b, 0
  %lnotuv = xor i1 %luv, true
  %bneg = and i1 %bneg0, %lnotuv
  %bn = sub i64 0, %b
  %bu = select i1 %bneg, i64 %bn, i64 %b
  %bm1 = sub i64 %bu, 1
  %band = and i64 %bu, %bm1
  %pow2 = icmp eq i64 %band, 0
  %lz = call i64 @llvm.ctlz.i64(i64 %bu, i1 false)
  %hb = sub i64 64, %lz
  %pbig = icmp ugt i64 %p, 64
  %prod = mul i64 %p, %hb
  %pfit = icmp ule i64 %prod, 64
  %fit0 = xor i1 %pbig, 1
  %fit1 = and i1 %fit0, %pfit
  %np = xor i1 %pneg, 1
  %np2 = xor i1 %pow2, 1
  %fit2 = and i1 %fit1, %np
  %fit = and i1 %fit2, %np2
  br i1 %fit, label %loop, label %float
loop:
  %i = phi i64 [ 0, %ints ], [ %i2, %step ]
  %acc = phi i64 [ 1, %ints ], [ %acc2, %step ]
  %more = icmp slt i64 %i, %p
  br i1 %more, label %step, label %done
step:
  %acc2 = mul i64 %acc, %bu
  %i2 = add i64 %i, 1
  br label %loop
done:
  %odd = and i64 %p, 1
  %isodd = icmp eq i64 %odd, 1
  %negres = and i1 %bneg, %isodd
  br i1 %negres, label %neg, label %pos
pos:
  %ps = call %Slot @t2_box_uv(i64 %acc)
  ret %Slot %ps
neg:
  %wa = zext i64 %acc to i128
  %wn = sub i128 0, %wa
  %ns = call %Slot @t2_int_or_nv(i128 %wn, i1 1)
  ret %Slot %ns
float:
  %ld = call double @t2_slot_num(%Slot %l)
  %rd = call double @t2_slot_num(%Slot %r)
  %f = call double @llvm.pow.f64(double %ld, double %rd)
  %fs = call %Slot @t2_box_num(double %f)
  ret %Slot %fs
}
; t2_hexoct(s, oct, warn) -> perl\'s hex (oct false) or oct of a string
; (pp_oct; grok_hex, grok_oct, grok_bin): oct skips leading space, then a
; "0", then "x" is hex, "b" binary, "o" octal (octal anyway); hex takes an
; "x" or "0x". Digits of the base, an "_" before each, until the first that
; is not one. A UV (past IV_MAX, a UV). Past UV_MAX perl warns and gives an
; NV; where the program enables warnings, a character that is not a digit
; (of octal\'s, an 8 or a 9), or a value past 32 bits, warns too -- each
; stopped by name, not guessed.
@msg_hexoct = private unnamed_addr constant [83 x i8] c"a hex or oct past UV_MAX, or one perl warns of (warnings on): stopped (chalk, T2)\0A\00"
define internal %Slot @t2_hexoct(%Str %s, i1 %oct, i1 %warn) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  br i1 %oct, label %ows, label %hexpre
ows:
  %i0 = phi i64 [ 0, %entry ], [ %i0n, %owsn ]
  %e0 = icmp sge i64 %i0, %n
  br i1 %e0, label %oz, label %owsc
owsc:
  %c0p = getelementptr i8, i8* %p, i64 %i0
  %c0 = load i8, i8* %c0p
  %sp = icmp eq i8 %c0, 32
  %t1 = icmp uge i8 %c0, 9
  %t2 = icmp ule i8 %c0, 13
  %ctl = and i1 %t1, %t2
  %white = or i1 %sp, %ctl
  br i1 %white, label %owsn, label %oz
owsn:
  %i0n = add i64 %i0, 1
  br label %ows
oz:
  %i1 = phi i64 [ %i0, %ows ], [ %i0, %owsc ]
  %c1 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i1)
  %z1 = icmp eq i8 %c1, 48
  %i1z = add i64 %i1, 1
  %i2 = select i1 %z1, i64 %i1z, i64 %i1
  %c2 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i2)
  %c2l = or i8 %c2, 32
  %isx = icmp eq i8 %c2l, 120
  %isb = icmp eq i8 %c2l, 98
  %iso = icmp eq i8 %c2l, 111
  %i2n = add i64 %i2, 1
  %pre = or i1 %isx, %isb
  %pre2 = or i1 %pre, %iso
  %i3 = select i1 %pre2, i64 %i2n, i64 %i2
  %b0 = select i1 %isb, i64 2, i64 8
  %ob = select i1 %isx, i64 16, i64 %b0
  br label %digits
hexpre:
  %h0 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 0)
  %h1 = call i8 @t2_byte_at(i8* %p, i64 %n, i64 1)
  %h0l = or i8 %h0, 32
  %h1l = or i8 %h1, 32
  %hx0 = icmp eq i8 %h0l, 120
  %hz = icmp eq i8 %h0, 48
  %hx1 = icmp eq i8 %h1l, 120
  %h01 = and i1 %hz, %hx1
  %hs1 = select i1 %hx0, i64 1, i64 0
  %hs = select i1 %h01, i64 2, i64 %hs1
  br label %digits
digits:
  %start = phi i64 [ %i3, %oz ], [ %hs, %hexpre ]
  %base = phi i64 [ %ob, %oz ], [ 16, %hexpre ]
  br label %loop
loop:
  %i = phi i64 [ %start, %digits ], [ %inext, %take ]
  %acc = phi i64 [ 0, %digits ], [ %acc2, %take ]
  %end = icmp sge i64 %i, %n
  br i1 %end, label %done, label %look
look:
  %c = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %i)
  %d = call i64 @t2_digit_of(i8 %c, i64 %base)
  %ok = icmp sge i64 %d, 0
  br i1 %ok, label %take0, label %under
under:
  %isu = icmp eq i8 %c, 95
  %ip1 = add i64 %i, 1
  %cn = call i8 @t2_byte_at(i8* %p, i64 %n, i64 %ip1)
  %dn = call i64 @t2_digit_of(i8 %cn, i64 %base)
  %okn = icmp sge i64 %dn, 0
  %uok = and i1 %isu, %okn
  br i1 %uok, label %take1, label %bad
take0:
  br label %take
take1:
  br label %take
take:
  %dd = phi i64 [ %d, %take0 ], [ %dn, %take1 ]
  %adv = phi i64 [ 1, %take0 ], [ 2, %take1 ]
  %inext = add i64 %i, %adv
  %r = call { i64, i1 } @llvm.umul.with.overflow.i64(i64 %acc, i64 %base)
  %m = extractvalue { i64, i1 } %r, 0
  %o1 = extractvalue { i64, i1 } %r, 1
  %a = call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %m, i64 %dd)
  %acc2 = extractvalue { i64, i1 } %a, 0
  %o2 = extractvalue { i64, i1 } %a, 1
  %ov = or i1 %o1, %o2
  br i1 %ov, label %stop, label %loop
bad:
  ; (a character that is not a digit ends it: perl warns of it where warnings
  ; are on -- of octal\'s only an 8 or a 9)
  %bc0 = icmp uge i8 %c, 48
  %bc1 = icmp ule i8 %c, 57
  %bdig = and i1 %bc0, %bc1
  %b8 = icmp eq i64 %base, 8
  %quiet = xor i1 %bdig, true
  %oquiet = and i1 %b8, %quiet
  %loud = xor i1 %oquiet, true
  %wl = and i1 %warn, %loud
  br i1 %wl, label %stop, label %done
done:
  %big = icmp ugt i64 %acc, 4294967295
  %wbig = and i1 %big, %warn
  br i1 %wbig, label %stop, label %ret
ret:
  %rs = call %Slot @t2_box_uv(i64 %acc)
  ret %Slot %rs
stop:
  call void @t2_stop(i8* getelementptr ([83 x i8], [83 x i8]* @msg_hexoct, i64 0, i64 0), i64 82)
  unreachable
}
declare { i64, i1 } @llvm.uadd.with.overflow.i64(i64, i64)
; t2_digit_of(c, base) -> c\'s value as a digit of base (2, 8, 16), or -1.
define internal i64 @t2_digit_of(i8 %c, i64 %base) {
entry:
  %d0 = icmp uge i8 %c, 48
  %d1 = icmp ule i8 %c, 57
  %dig = and i1 %d0, %d1
  %lc = or i8 %c, 32
  %l0 = icmp uge i8 %lc, 97
  %l1 = icmp ule i8 %lc, 102
  %let = and i1 %l0, %l1
  %cz = zext i8 %c to i64
  %lz = zext i8 %lc to i64
  %vd = sub i64 %cz, 48
  %vl = sub i64 %lz, 87
  %v0 = select i1 %let, i64 %vl, i64 -1
  %v = select i1 %dig, i64 %vd, i64 %v0
  %lt = icmp ult i64 %v, %base
  %r = select i1 %lt, i64 %v, i64 -1
  ret i64 %r
}
; ---- perl\'s bitwise operators (pp_bit_and & co.) ----
; t2_bit_uv(v): a value\'s bits as perl\'s SvUV reads them (no `use
; integer`): an IV\'s own (as a UV: -1 is UV_MAX), a UV\'s, an NV\'s cast_uv,
; a string\'s integer read whole (9007199254740993 kept its 3).
define internal i64 @t2_bit_uv(%Slot %v0) {
  %r = call i64 @t2_slot_i64(%Slot %v0)
  ret i64 %r
}
; t2_bit_num(r, inner) -> a bitwise op\'s result: perl\'s UV (past IV_MAX, a UV).
define internal %Slot @t2_bit_num(i64 %r, i1 %inner) {
  %s = call %Slot @t2_box_uv(i64 %r)
  ret %Slot %s
}
; t2_bitop(a, b, op, mode, inner): op 0 &, 1 |, 2 ^, 3 ~ (b unused). Mode
; 1 on numbers, 2 on strings\' bytes, 0 perl\'s choice: bytes where every
; operand is a string (tag 3), numbers otherwise.
define internal %Slot @t2_bitop(%Slot %a, %Slot %b, i64 %op, i64 %mode, i1 %inner) {
entry:
  %ta = extractvalue %Slot %a, 0
  %tb = extractvalue %Slot %b, 0
  %sa = icmp eq i8 %ta, 3
  %sb0 = icmp eq i8 %tb, 3
  %isnot = icmp eq i64 %op, 3
  %sb = or i1 %sb0, %isnot
  %both = and i1 %sa, %sb
  %m0 = icmp eq i64 %mode, 0
  %m2 = icmp eq i64 %mode, 2
  %by0 = and i1 %m0, %both
  %bytes = or i1 %by0, %m2
  br i1 %bytes, label %str, label %num
num:
  %x = call i64 @t2_bit_uv(%Slot %a)
  br i1 %isnot, label %nnot, label %nbin
nnot:
  %rn = xor i64 %x, -1
  %sn = call %Slot @t2_bit_num(i64 %rn, i1 %inner)
  ret %Slot %sn
nbin:
  %y = call i64 @t2_bit_uv(%Slot %b)
  %r0 = and i64 %x, %y
  %r1 = or i64 %x, %y
  %r2 = xor i64 %x, %y
  %is1 = icmp eq i64 %op, 1
  %is2 = icmp eq i64 %op, 2
  %r01 = select i1 %is1, i64 %r1, i64 %r0
  %r = select i1 %is2, i64 %r2, i64 %r01
  %sr = call %Slot @t2_bit_num(i64 %r, i1 %inner)
  ret %Slot %sr
str:
  %as = call %Str @t2_slot_str(%Slot %a)
  %bs = call %Str @t2_slot_str(%Slot %b)
  %ap = extractvalue %Str %as, 0
  %an = extractvalue %Str %as, 1
  %bp = extractvalue %Str %bs, 0
  %bn0 = extractvalue %Str %bs, 1
  %bn = select i1 %isnot, i64 0, i64 %bn0
  %alt = icmp slt i64 %an, %bn
  %mn = select i1 %alt, i64 %an, i64 %bn
  %mx = select i1 %alt, i64 %bn, i64 %an
  %isand = icmp eq i64 %op, 0
  %is1s = icmp eq i64 %op, 1
  %is2s = icmp eq i64 %op, 2
  %n0 = select i1 %isand, i64 %mn, i64 %mx
  %n = select i1 %isnot, i64 %an, i64 %n0
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  %e = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %e
  br label %loop
loop:
  %i = phi i64 [ 0, %str ], [ %i2, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ina = icmp slt i64 %i, %an
  %inb = icmp slt i64 %i, %bn
  %pa = getelementptr i8, i8* %ap, i64 %i
  %pb = getelementptr i8, i8* %bp, i64 %i
  %z = getelementptr [1 x i8], [1 x i8]* @t2_empty, i64 0, i64 0
  %qa = select i1 %ina, i8* %pa, i8* %z
  %qb = select i1 %inb, i8* %pb, i8* %z
  %ca0 = load i8, i8* %qa
  %cb0 = load i8, i8* %qb
  %ca = select i1 %ina, i8 %ca0, i8 0
  %cb = select i1 %inb, i8 %cb0, i8 0
  %c0 = and i8 %ca, %cb
  %c1 = or i8 %ca, %cb
  %c2 = xor i8 %ca, %cb
  %c3 = xor i8 %ca, -1
  %c01 = select i1 %is1s, i8 %c1, i8 %c0
  %c012 = select i1 %is2s, i8 %c2, i8 %c01
  %c = select i1 %isnot, i8 %c3, i8 %c012
  %dst = getelementptr i8, i8* %buf, i64 %i
  store i8 %c, i8* %dst
  %i2 = add i64 %i, 1
  br label %loop
done:
  %rs = call %Str @t2_str(i8* %buf, i64 %n)
  %rb = call %Slot @t2_box_str(%Str %rs)
  ret %Slot %rb
}
; t2_bit_numeric(a, b, fa, fb, op) -> perl\'s choice (t2_bitop\'s mode 0)
; is on numbers: an operand is not a string (tag 3), or is one an op before
; made a number (fa, fb) -- ~ (op 3) reads a alone.
define internal i1 @t2_bit_numeric(%Slot %a, %Slot %b, i1 %fa, i1 %fb, i64 %op) {
  %ta = extractvalue %Slot %a, 0
  %tb = extractvalue %Slot %b, 0
  %sa = icmp eq i8 %ta, 3
  %sb0 = icmp eq i8 %tb, 3
  %isnot = icmp eq i64 %op, 3
  %sb = or i1 %sb0, %isnot
  %both = and i1 %sa, %sb
  %num0 = xor i1 %both, true
  %f = or i1 %fa, %fb
  %num = or i1 %num0, %f
  ret i1 %num
}
; t2_bit_numified(was, num, x) -> x, a string, made a number by an op done
; on numbers (num) -- or by one before (was).
define internal i1 @t2_bit_numified(i1 %was, i1 %num, %Slot %x) {
  %t = extractvalue %Slot %x, 0
  %s = icmp eq i8 %t, 3
  %now = and i1 %num, %s
  %r = or i1 %was, %now
  ret i1 %r
}
; t2_bitop_made(a, b, fa, fb, op, inner): t2_bitop\'s perl\'s choice, where
; an operand a string an op before made a number (fa, fb) is a number.
define internal %Slot @t2_bitop_made(%Slot %a, %Slot %b, i1 %fa, i1 %fb, i64 %op, i1 %inner) {
  %f = or i1 %fa, %fb
  %mode = select i1 %f, i64 1, i64 0
  %r = call %Slot @t2_bitop(%Slot %a, %Slot %b, i64 %op, i64 %mode, i1 %inner)
  ret %Slot %r
}
; t2_shift(a, n, left, inner): perl\'s << and >> on a UV: a negative count
; shifts the other way, one of 64 or more gives 0.
define internal %Slot @t2_shift(%Slot %a, %Slot %b, i1 %left, i1 %inner) {
entry:
  %x = call i64 @t2_bit_uv(%Slot %a)
  %n0 = call i64 @t2_bit_uv(%Slot %b)
  %nneg = icmp slt i64 %n0, 0
  %nn = sub i64 0, %n0
  %n = select i1 %nneg, i64 %nn, i64 %n0
  %l0 = xor i1 %left, %nneg
  %big = icmp uge i64 %n, 64
  %ns = select i1 %big, i64 0, i64 %n
  %rl = shl i64 %x, %ns
  %rr = lshr i64 %x, %ns
  %r0 = select i1 %l0, i64 %rl, i64 %rr
  %r = select i1 %big, i64 0, i64 %r0
  %s = call %Slot @t2_bit_num(i64 %r, i1 %inner)
  ret %Slot %s
}
; ---- IN-MEMORY HANDLES: open(my $fh, "<", \"...") reads the string; open(my
; $fh, ">", \my $buf) writes into $buf. A handle is { i8* data, i64 len, i64
; pos, %Slot* target } (malloc\'d), held in a %Slot (tag 1, its address);
; undef where none is open. DATA is one, on the program\'s __DATA__ text.
%Fh = type { i8*, i64, i64, %Slot* }
declare i8* @memchr(i8*, i32, i64)
@t2_selected = internal global %Slot zeroinitializer
@t2_data_fh = internal global %Slot zeroinitializer
@lit_stdout = private unnamed_addr constant [13 x i8] c"main::STDOUT\00"
@msg_select = private unnamed_addr constant [62 x i8] c"select of a handle T2 holds as no value: stopped (chalk, T2)\0A\00"
define internal %Fh* @t2_fh_ptr(%Slot %h) {
  %t = extractvalue %Slot %h, 0
  %open = icmp eq i8 %t, 1
  %v = extractvalue %Slot %h, 1
  %p = inttoptr i64 %v to %Fh*
  %r = select i1 %open, %Fh* %p, %Fh* null
  ret %Fh* %r
}
define internal %Slot @t2_fh_new(i8* %d, i64 %n, %Slot* %t) {
  %m = call i8* @malloc(i64 32)
  %f = bitcast i8* %m to %Fh*
  %f0 = getelementptr %Fh, %Fh* %f, i32 0, i32 0
  store i8* %d, i8** %f0
  %f1 = getelementptr %Fh, %Fh* %f, i32 0, i32 1
  store i64 %n, i64* %f1
  %f2 = getelementptr %Fh, %Fh* %f, i32 0, i32 2
  store i64 0, i64* %f2
  %f3 = getelementptr %Fh, %Fh* %f, i32 0, i32 3
  store %Slot* %t, %Slot** %f3
  %i = ptrtoint i8* %m to i64
  %s = call %Slot @t2_slot(i8 1, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_fh_ropen(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %h = call %Slot @t2_fh_new(i8* %p, i64 %n, %Slot* null)
  ret %Slot %h
}
; ">" empties the scalar; ">>" appends to what it holds.
define internal %Slot @t2_fh_wopen(%Slot* %t, i1 %trunc) {
entry:
  br i1 %trunc, label %empty, label %go
empty:
  %e = call %Str @t2_str(i8* getelementptr ([1 x i8], [1 x i8]* @t2_empty, i64 0, i64 0), i64 0)
  %es = call %Slot @t2_box_str(%Str %e)
  store %Slot %es, %Slot* %t
  br label %go
go:
  %h = call %Slot @t2_fh_new(i8* null, i64 0, %Slot* %t)
  ret %Slot %h
}
define internal %Slot @t2_fh_data(%Str %s) {
entry:
  %h = load %Slot, %Slot* @t2_data_fh
  %t = extractvalue %Slot %h, 0
  %made = icmp eq i8 %t, 1
  br i1 %made, label %ok, label %mk
mk:
  %n = call %Slot @t2_fh_ropen(%Str %s)
  store %Slot %n, %Slot* @t2_data_fh
  ret %Slot %n
ok:
  ret %Slot %h
}
; readline: the next line (its newline kept), undef at the end or unopened.
define internal %Slot @t2_fh_readline(%Slot %h) {
entry:
  %f = call %Fh* @t2_fh_ptr(%Slot %h)
  %none = icmp eq %Fh* %f, null
  br i1 %none, label %undef, label %chk
chk:
  %f0 = getelementptr %Fh, %Fh* %f, i32 0, i32 0
  %d = load i8*, i8** %f0
  %f1 = getelementptr %Fh, %Fh* %f, i32 0, i32 1
  %n = load i64, i64* %f1
  %f2 = getelementptr %Fh, %Fh* %f, i32 0, i32 2
  %pos = load i64, i64* %f2
  %more = icmp slt i64 %pos, %n
  br i1 %more, label %read, label %undef
read:
  %rest = getelementptr i8, i8* %d, i64 %pos
  %rl = sub i64 %n, %pos
  %nl = call i8* @memchr(i8* %rest, i32 10, i64 %rl)
  %found = icmp ne i8* %nl, null
  %nli = ptrtoint i8* %nl to i64
  %ri = ptrtoint i8* %rest to i64
  %off = sub i64 %nli, %ri
  %off1 = add i64 %off, 1
  %ll = select i1 %found, i64 %off1, i64 %rl
  %np = add i64 %pos, %ll
  store i64 %np, i64* %f2
  %ll1 = add i64 %ll, 1
  %buf = call i8* @malloc(i64 %ll1)
  call i8* @memcpy(i8* %buf, i8* %rest, i64 %ll)
  %end = getelementptr i8, i8* %buf, i64 %ll
  store i8 0, i8* %end
  %line = call %Str @t2_str(i8* %buf, i64 %ll)
  %ls = call %Slot @t2_box_str(%Str %line)
  ret %Slot %ls
undef:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
}
define internal %Array* @t2_fh_readlines(%Slot %h) {
entry:
  %a = call %Array* @t2_new_array()
  br label %loop
loop:
  %l = call %Slot @t2_fh_readline(%Slot %h)
  %t = extractvalue %Slot %l, 0
  %end = icmp eq i8 %t, 0
  br i1 %end, label %done, label %push
push:
  call void @t2_apush(%Array* %a, %Slot %l)
  br label %loop
done:
  ret %Array* %a
}
define internal i1 @t2_fh_eof(%Slot %h) {
entry:
  %f = call %Fh* @t2_fh_ptr(%Slot %h)
  %none = icmp eq %Fh* %f, null
  br i1 %none, label %yes, label %chk
chk:
  %f1 = getelementptr %Fh, %Fh* %f, i32 0, i32 1
  %n = load i64, i64* %f1
  %f2 = getelementptr %Fh, %Fh* %f, i32 0, i32 2
  %pos = load i64, i64* %f2
  %at = icmp sge i64 %pos, %n
  ret i1 %at
yes:
  ret i1 1
}
; a print to a handle: appended to its scalar -- true; to one not open for
; writing (closed, never opened, open for reading), nothing -- false, as perl\'s.
@msg_fh_undef = private unnamed_addr constant [65 x i8] c"a print to an undefined handle (perl dies): stopped (chalk, T2)\0A\00"
define internal i1 @t2_fh_print(%Slot %h, %Str %s) {
entry:
  ; (to a `my $fh` never opened -- undef -- perl dies: "Can\'t use an
  ; undefined value as a symbol reference")
  %ht = extractvalue %Slot %h, 0
  %undef = icmp eq i8 %ht, 0
  br i1 %undef, label %die, label %go
die:
  call void @t2_stop(i8* getelementptr ([65 x i8], [65 x i8]* @msg_fh_undef, i64 0, i64 0), i64 64)
  unreachable
go:
  %f = call %Fh* @t2_fh_ptr(%Slot %h)
  %none = icmp eq %Fh* %f, null
  br i1 %none, label %no, label %chk
chk:
  %f3 = getelementptr %Fh, %Fh* %f, i32 0, i32 3
  %t = load %Slot*, %Slot** %f3
  %not = icmp eq %Slot* %t, null
  br i1 %not, label %no, label %write
write:
  %old = load %Slot, %Slot* %t
  %os = call %Str @t2_slot_str(%Slot %old)
  %ns = call %Str @t2_concat(%Str %os, %Str %s)
  %nv = call %Slot @t2_box_str(%Str %ns)
  store %Slot %nv, %Slot* %t
  ret i1 1
no:
  ret i1 0
}
; close: the handle itself shut (select may hold it): nothing left to read,
; nowhere to write. True where it was open.
define internal i1 @t2_fh_close(%Slot %h) {
entry:
  %f = call %Fh* @t2_fh_ptr(%Slot %h)
  %none = icmp eq %Fh* %f, null
  br i1 %none, label %no, label %shut
shut:
  %f1 = getelementptr %Fh, %Fh* %f, i32 0, i32 1
  store i64 0, i64* %f1
  %f3 = getelementptr %Fh, %Fh* %f, i32 0, i32 3
  store %Slot* null, %Slot** %f3
  ret i1 1
no:
  ret i1 0
}
; print with no handle, in a program that selects one: to the one selected.
define internal i1 @t2_print_sel(%Str %s) {
entry:
  %h = load %Slot, %Slot* @t2_selected
  %t = extractvalue %Slot %h, 0
  %std = icmp eq i8 %t, 0
  br i1 %std, label %out, label %fh
out:
  call void @t2_print(%Str %s)
  ret i1 1
fh:
  %ok = call i1 @t2_fh_print(%Slot %h, %Str %s)
  ret i1 %ok
}
; select(h, used): h the selected handle (undef STDOUT); the one before
; handed back -- STDOUT\'s name, or (where it is used) a stop where it was a
; handle.
define internal %Slot @t2_select(%Slot %h, i1 %used) {
entry:
  %old = load %Slot, %Slot* @t2_selected
  store %Slot %h, %Slot* @t2_selected
  %t = extractvalue %Slot %old, 0
  %std = icmp eq i8 %t, 0
  %unused = xor i1 %used, 1
  %ok = or i1 %std, %unused
  br i1 %ok, label %name, label %stop
name:
  %s = call %Str @t2_str(i8* getelementptr ([13 x i8], [13 x i8]* @lit_stdout, i64 0, i64 0), i64 12)
  %ss = call %Slot @t2_box_str(%Str %s)
  ret %Slot %ss
stop:
  call void @t2_stop(i8* getelementptr ([62 x i8], [62 x i8]* @msg_select, i64 0, i64 0), i64 61)
  unreachable
}
; select($fh): a `my $fh` never opened (undef) is no handle -- what is printed
; then goes nowhere (a handle of address 0), not to STDOUT.
define internal %Slot @t2_select_fh(%Slot %h, i1 %used) {
entry:
  %t = extractvalue %Slot %h, 0
  %undef = icmp eq i8 %t, 0
  %none = call %Slot @t2_slot(i8 1, i64 0)
  %hh = select i1 %undef, %Slot %none, %Slot %h
  %r = call %Slot @t2_select(%Slot %hh, i1 %used)
  ret %Slot %r
}
; select(NAME): STDOUT by its name; another, a stop.
define internal %Slot @t2_select_name(%Slot %v, i1 %used) {
entry:
  %s = call %Str @t2_slot_str(%Slot %v)
  %want = call %Str @t2_str(i8* getelementptr ([13 x i8], [13 x i8]* @lit_stdout, i64 0, i64 0), i64 12)
  %c = call i64 @t2_strcmp(%Str %s, %Str %want)
  %is = icmp eq i64 %c, 0
  br i1 %is, label %std, label %stop
std:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  %r = call %Slot @t2_select(%Slot %u, i1 %used)
  ret %Slot %r
stop:
  call void @t2_stop(i8* getelementptr ([62 x i8], [62 x i8]* @msg_select, i64 0, i64 0), i64 61)
  unreachable
}
; ---- formats (formline) ----
declare i8* @memset(i8*, i32, i64)
; t2_form_field(v, w, right): a format\'s @<<< (or @>>>) field: v up to its
; first newline, cut to w, padded with spaces to w (on the left if right).
define internal %Str @t2_form_field(%Slot %v, i64 %w, i1 %right) {
entry:
  %s = call %Str @t2_slot_str(%Slot %v)
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %nl = call i8* @memchr(i8* %p, i32 10, i64 %n)
  %has = icmp ne i8* %nl, null
  %nli = ptrtoint i8* %nl to i64
  %pi = ptrtoint i8* %p to i64
  %upto = sub i64 %nli, %pi
  %l0 = select i1 %has, i64 %upto, i64 %n
  %long = icmp sgt i64 %l0, %w
  %l = select i1 %long, i64 %w, i64 %l0
  %w1 = add i64 %w, 1
  %buf = call i8* @malloc(i64 %w1)
  call i8* @memset(i8* %buf, i32 32, i64 %w)
  %pad = sub i64 %w, %l
  %at = select i1 %right, i64 %pad, i64 0
  %dst = getelementptr i8, i8* %buf, i64 %at
  call i8* @memcpy(i8* %dst, i8* %p, i64 %l)
  %e = getelementptr i8, i8* %buf, i64 %w
  store i8 0, i8* %e
  %r = call %Str @t2_str(i8* %buf, i64 %w)
  ret %Str %r
}
; t2_rtrim(s): s without its trailing spaces (a format line\'s, as formline chops them).
define internal %Str @t2_rtrim(%Str %s) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  br label %loop
loop:
  %k = phi i64 [ %n, %entry ], [ %k1, %back ]
  %any = icmp sgt i64 %k, 0
  br i1 %any, label %chk, label %done
chk:
  %k1 = sub i64 %k, 1
  %cp = getelementptr i8, i8* %p, i64 %k1
  %c = load i8, i8* %cp
  %sp = icmp eq i8 %c, 32
  br i1 %sp, label %back, label %done
back:
  br label %loop
done:
  %r = call %Str @t2_str(i8* %p, i64 %k)
  ret %Str %r
}
; ---- isa, a method named at run time ----
; `$o isa C`: o a blessed reference whose class is, or inherits from, C.
define internal i1 @t2_isa_op(%Slot %o, %Str %c) {
entry:
  %cl = call %Slot @t2_class_of(%Slot %o)
  %t = extractvalue %Slot %cl, 0
  %none = icmp eq i8 %t, 0
  br i1 %none, label %no, label %walk
walk:
  %cs = call %Str @t2_slot_str(%Slot %cl)
  %r = call i1 @t2_isa_walk(%Str %cs, %Str %c)
  ret i1 %r
no:
  ret i1 0
}
@msg_dyn = private unnamed_addr constant [76 x i8] c"a method named at run time by other than a plain name: stopped (chalk, T2)\0A\00"
; t2_dyn_name(m): `$o->$m`\'s name -- a string with no package in it; a code
; value (perl calls it) or a qualified name, a stop.
define internal %Str @t2_dyn_name(%Slot %m) {
entry:
  %t = extractvalue %Slot %m, 0
  %isstr = icmp eq i8 %t, 3
  br i1 %isstr, label %chk, label %stop
chk:
  %s = call %Str @t2_slot_str(%Slot %m)
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %c1 = call i8* @memchr(i8* %p, i32 58, i64 %n)
  %c2 = call i8* @memchr(i8* %p, i32 39, i64 %n)
  %h1 = icmp ne i8* %c1, null
  %h2 = icmp ne i8* %c2, null
  %bad = or i1 %h1, %h2
  br i1 %bad, label %stop, label %ok
ok:
  ret %Str %s
stop:
  call void @t2_stop(i8* getelementptr ([76 x i8], [76 x i8]* @msg_dyn, i64 0, i64 0), i64 75)
  unreachable
}
; ---- chomp and chop of a value ----
; t2_chomp_n(s, chop) -> how many chars chomp ("\n" at the end: 1) or chop (any: 1) takes off.
define internal i64 @t2_chomp_n(%Str %s, i1 %chop) {
entry:
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %none, label %last
last:
  br i1 %chop, label %one, label %nl
nl:
  %k = sub i64 %n, 1
  %lp = getelementptr i8, i8* %p, i64 %k
  %c = load i8, i8* %lp
  %is = icmp eq i8 %c, 10
  br i1 %is, label %one, label %none
one:
  ret i64 1
none:
  ret i64 0
}
; t2_chop_char(s) -> what chop takes off: the last character, or "" of "".
define internal %Str @t2_chop_char(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %k = call i64 @t2_chomp_n(%Str %s, i1 1)
  %m = sub i64 %n, %k
  %q = getelementptr i8, i8* %p, i64 %m
  %r = call %Str @t2_str(i8* %q, i64 %k)
  ret %Str %r
}
define internal %Str @t2_chomp(%Str %s, i1 %chop) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %k = call i64 @t2_chomp_n(%Str %s, i1 %chop)
  %m = sub i64 %n, %k
  %r = call %Str @t2_str(i8* %p, i64 %m)
  ret %Str %r
}
; ---- each: a hash\'s iterator, by its address ----
@t2_iters = internal global %Slot zeroinitializer
define internal %Array* @t2_each(%Slot %h) {
entry:
  %tb = call %Slot @t2_ghash(%Slot* @t2_iters)
  %k = call %Str @t2_addr_key(%Slot %h)
  %ps = call %Slot @t2_hget(%Slot %tb, %Str %k)
  %pos = call i64 @t2_slot_i64(%Slot %ps)
  %n = call i64 @t2_hcount(%Slot %h)
  %r = call %Array* @t2_new_array()
  %end = icmp sge i64 %pos, %n
  br i1 %end, label %done, label %next
done:
  %z = call %Slot @t2_box_i64(i64 0)
  call void @t2_hset(%Slot %tb, %Str %k, %Slot %z)
  ret %Array* %r
next:
  %ks = call %Array* @t2_hkeys(%Slot %h)
  %vs = call %Array* @t2_hvalues(%Slot %h)
  %kv = call %Slot @t2_aget(%Array* %ks, i64 %pos)
  %vv = call %Slot @t2_aget(%Array* %vs, i64 %pos)
  call void @t2_apush(%Array* %r, %Slot %kv)
  call void @t2_apush(%Array* %r, %Slot %vv)
  %p1 = add i64 %pos, 1
  %ns = call %Slot @t2_box_i64(i64 %p1)
  call void @t2_hset(%Slot %tb, %Str %k, %Slot %ns)
  ret %Array* %r
}
' }

1;
