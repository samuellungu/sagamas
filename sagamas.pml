#ifndef N
#define N 3
#endif

mtype = { START_TRANSACTION, SUBTRANSACTION_EXEC, SUCCESS, FAILURE,
          COMPENSATE, COMP_DONE, DONE, DONE_ACK };

/* channels */
chan c_to[N]   = [2] of { mtype, byte };
chan c_from[N] = [2] of { mtype, byte };

/* ---- Global propositions & bookkeeping ---- */
bool reached_progress = false;   /* set at progress point */
bool g_completed      = false;   /* set true on commit path */
bool g_aborted        = false;   /* set true on failure/compensation path */

bool dispatched[N];              /* Coordinator sent SUBTRANSACTION_EXEC to i */
bool answered[N];                /* Coordinator received SUCCESS/FAILURE from i */
bool succeeded[N];               /* Coordinator received SUCCESS from i */
bool compensated[N];             /* Coordinator observed COMP_DONE for i during abort */
bool shutdown_seen[N];           /* Participant i observed DONE */
byte shutdown_count = 0;         /* count of participants that saw DONE */

/* ------------- Participant ------------- */
proctype Participant(byte id)
{
    byte tr;
end_wait:
    do
    :: c_to[id]?SUBTRANSACTION_EXEC, tr ->
        if
        :: c_from[id]!SUCCESS, tr
        :: c_from[id]!FAILURE, tr
        fi
    :: c_to[id]?COMPENSATE, tr ->
        c_from[id]!COMP_DONE, tr
    :: c_to[id]?DONE, tr ->
        if
        :: !shutdown_seen[id] ->
            shutdown_seen[id] = true;
            shutdown_count++
        :: else -> skip
        fi;
        /* Send ACK and terminate */
        c_from[id]!DONE_ACK, tr;
        break
    od
}

/* ------------- Coordinator ------------- */
proctype Coordinator()
{
    byte i = 0;
    byte tr = 1;
    bool aborted = false;  /* local; mirrored by g_aborted when set */

    /* Initialize bookkeeping (explicit zeroing) */
    i = 0;
    do
    :: i < N ->
        dispatched[i] = false;
        answered[i]   = false;
        succeeded[i]  = false;
        compensated[i]= false;
        shutdown_seen[i] = false;
        i++
    :: else -> break
    od;
    i = 0;

    /* sequential subtransactions; stop when aborted */
    do
    :: (i < N && !aborted) ->
        dispatched[i] = true;
        c_to[i]!SUBTRANSACTION_EXEC, tr;
        do
        :: c_from[i]?SUCCESS, tr ->
            answered[i]  = true;
            succeeded[i] = true;
            i++; break
        :: c_from[i]?FAILURE, tr ->
            answered[i]  = true;
            aborted      = true;
            g_aborted    = true;
            break
        od
    :: else -> break
    od;

    if
    :: aborted ->
        /* compensate successful ones in reverse order */
        do
        :: i > 0 ->
            i--;
            if
            :: succeeded[i] ->
                c_to[i]!COMPENSATE, tr;
                c_from[i]?COMP_DONE, tr;
                compensated[i] = true
            :: else -> skip
            fi
        :: else -> break
        od
    :: else ->
        g_completed = true
    fi;

progress:
    atomic {
        reached_progress = true;
        /* broadcast DONE */
        i = 0;
        do
        :: i < N -> c_to[i]!DONE, tr; i++
        :: else -> break
        od
    }

    /* wait for DONE_ACK from all participants before exiting */
    i = 0;
    do
    :: i < N ->
        c_from[i]?DONE_ACK, tr;
        i++
    :: else -> break
    od;

    /* ---- Safety assertions at saga end ---- */
    assert(g_completed || g_aborted);               /* must decide */
    assert(!(g_completed && g_aborted));            /* not both */
    /* Compensation implies prior success */
    i = 0;
    do
    :: i < N ->
        assert(!compensated[i] || succeeded[i]);
        i++
    :: else -> break
    od;
    /* If committed, then nobody should have been compensated */
    if
    :: g_completed ->
        i = 0;
        do
        :: i < N -> assert(!compensated[i]); i++
        :: else -> skip
        od
    :: else -> skip
    fi;

    /* Ensure all participants observed DONE */
    assert(shutdown_count == N);
}

/* ------------- init ------------- */
init {
    byte i = 0;
    printf("N=%d\\n", N);
    atomic {
        do
        :: i < N -> run Participant(i); i++
        :: else -> break
        od;
        run Coordinator();
    }
}

/* ---------------- LTL PROPERTIES ---------------- */
/* 1) Eventually reach progress (broadcast DONE) */
ltl reach { <> reached_progress }

/* 2) Eventually terminate (commit or abort reached) */
ltl termination { <> (g_completed || g_aborted) }

/* 3) Combined: eventually progress AND terminated */
ltl both { <> (reached_progress && (g_completed || g_aborted)) }

/* 4) Everyone eventually sees DONE */
ltl all_done { <> (shutdown_count == N) }

/* 5) Per-participant: if dispatched then eventually answered */
#if N > 0
ltl answered_0 { [] (dispatched[0] -> <> answered[0]) }
#endif
#if N > 1
ltl answered_1 { [] (dispatched[1] -> <> answered[1]) }
#endif
#if N > 2
ltl answered_2 { [] (dispatched[2] -> <> answered[2]) }
#endif
#if N > 3
ltl answered_3 { [] (dispatched[3] -> <> answered[3]) }
#endif
#if N > 4
ltl answered_4 { [] (dispatched[4] -> <> answered[4]) }
#endif
#if N > 5
ltl answered_5 { [] (dispatched[5] -> <> answered[5]) }
#endif
#if N > 6
ltl answered_6 { [] (dispatched[6] -> <> answered[6]) }
#endif
#if N > 7
ltl answered_7 { [] (dispatched[7] -> <> answered[7]) }
#endif

