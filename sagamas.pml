mtype = { START_TRANSACTION, SUBTRANSACTION_EXEC, SUCCESS, FAILURE, COMPENSATE, COMP_DONE };

#define N 4          /* set to any number >= 1 */
#define TR 1

/* Conflict predicate; customize as needed */
#define CONFLICT(i,j) (0)

chan c_to[N]   = [4] of { mtype, byte };
chan c_from[N] = [4] of { mtype, byte };

/* bookkeeping / atomic props */
byte pending   = 0;
byte completed = 0;
byte aborted   = 0;

/* execution state and compensation acks */
byte executing[N];
byte comp_ack[N];

/*** PARTICIPANT ***/
proctype Participant(byte id) {
    byte tr;
    do
    :: c_to[id]?SUBTRANSACTION_EXEC, tr ->
        /* nondet outcome */
        if
        :: c_from[id]!SUCCESS, tr
        :: c_from[id]!FAILURE, tr
        fi
    :: c_to[id]?COMPENSATE, tr ->
        c_from[id]!COMP_DONE, tr
    od
}

/*** COORDINATOR ***/
proctype Coordinator() {
    byte tr = TR;
    byte i;
    byte j;
    byte dispatched = 0;
    byte got = 0;
    byte comp = 0;

    /* dispatch to all participants (respect conflicts if you set CONFLICT) */
    i = 0;
    do
    :: i < N ->
        /* check conflicts with anyone executing */
        j = 0;
        do
        :: j < N ->
            if
            :: (executing[j] == 1 && CONFLICT(i,j)) -> break
            :: else -> j++
            fi
        :: else ->
            c_to[i]!SUBTRANSACTION_EXEC, tr;
            executing[i] = 1;
            pending++;
            dispatched++;
            i++
        od
    :: else -> break
    od;

    /* collect outcomes from any ready participant */
    do
    :: got < dispatched ->
        i = 0;
        do
        :: i < N ->
            if
            :: (len(c_from[i]) > 0) ->
                if
                :: c_from[i]?SUCCESS, tr -> pending--; executing[i]=0; got++
                :: c_from[i]?FAILURE, tr -> aborted=1; executing[i]=0; got++
                fi
            fi;
            i++
        :: else -> break
        od
    :: else -> break
    od;

    if
    :: aborted == 0 ->
        completed = 1
    :: else ->
        /* broadcast COMPENSATE to all */
        i = 0;
        do
        :: i < N -> c_to[i]!COMPENSATE, tr; i++
        :: else -> break
        od;

        /* reset comp_ack */
        i = 0;
        do :: i < N -> comp_ack[i] = 0; i++ :: else -> break od;

        /* wait for COMP_DONE from each participant (only once per i) */
        do
        :: comp < N ->
            i = 0;
            do
            :: i < N ->
                if
                :: (comp_ack[i] == 0 && len(c_from[i]) > 0) ->
                    if
                    :: c_from[i]?COMP_DONE, tr -> comp_ack[i]=1; comp++
                    fi
                fi;
                i++
            :: else -> break
            od
        :: else -> break
        od
    fi
}

/*** SYSTEM STARTUP ***/
init {
    atomic {
        run Coordinator();
        byte k = 0;
        do
        :: k < N -> run Participant(k); k++
        :: else -> break
        od
    }
}
