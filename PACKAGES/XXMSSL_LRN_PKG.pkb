CREATE OR REPLACE PACKAGE BODY APPS.XXMSSL_LRN_PKG IS
  /************************************************************************************
  * NAME:          XXMSSL_LRN_PKG                                                     *
  * PURPOSE:       XXMSSL_LRN_PKG(OR49)                                               *
  *                                                                                   *
  *   VER          DATE           AUTHOR           DESCRIPTION                        *
  *   ---------  ---------        -------------    ---------------                    *
  *   1.0        09-MAY-2014                     CREATED THIS PROCEDURE               *
  *   1.1        15-NOV-2019      ABHIJIT               RESOLEV LRN BUG               *
  *   1.2        24-DEC-2019        YASHWANT        RESOLEV LRN BUG
  *   1.3        11-SEP-2020      YASHWANT          APPLY LOG FOR SUN INV XFER AND INSERT
  *                                                  INTO LOG TABLE
  *   1.4        25-NOV-2020      DALJEET        ADDED MRN LOGIC
  *   1.5        10-jan-2025      Vikas          
  *   1.6        10-feb-2025       YAshwant       remove custom lot process and resubmit error record
  ************************************************************************************/

  --====================================
  -- GLOBAL VARIABLE DECLARATION
  --====================================
  G_ORG_ID     NUMBER := FND_GLOBAL.ORG_ID;
  G_RESP_ID    NUMBER := FND_GLOBAL.RESP_ID;
  G_APPL_ID    NUMBER := FND_GLOBAL.RESP_APPL_ID;
  G_USER_ID    NUMBER := FND_PROFILE.VALUE('USER_ID');
  G_LOGIN_ID   NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
  G_REQUEST_ID NUMBER;
  MY_ROWID     UROWID;

  PROCEDURE PRINT_LOG(P_MESSAGE VARCHAR2) IS
    L_SEQ NUMBER;
  BEGIN
    IF G_DEBUG_FLAG = 'Y' THEN
      L_SEQ := XXMSSL.XXMSSL_LRN_TRANS_LOG_SEQ.NEXTVAL;
    
      INSERT INTO XXMSSL.XXMSSL_LRN_TRANSACTIONS_LOG
      VALUES
        (L_SEQ, G_ACTION, G_LRN_NO, P_MESSAGE, SYSDATE);
    
      FND_FILE.PUT_LINE(FND_FILE.LOG, P_MESSAGE);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Error in insert log ' || SQLERRM);
  END;

  PROCEDURE PRINT_LOG(P_ACTION  IN VARCHAR2,
                      P_LRN_NO  IN VARCHAR2,
                      P_MESSAGE VARCHAR2) IS
    L_SEQ NUMBER;
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    IF G_DEBUG_FLAG = 'Y' THEN
      L_SEQ := XXMSSL.XXMSSL_LRN_TRANS_LOG_SEQ.NEXTVAL;
    
      INSERT INTO XXMSSL.XXMSSL_LRN_TRANSACTIONS_LOG
      VALUES
        (L_SEQ, P_ACTION, P_LRN_NO, P_MESSAGE, SYSDATE);
    
      FND_FILE.PUT_LINE(FND_FILE.LOG, P_MESSAGE);
      COMMIT;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Error in insert log ' || SQLERRM);
  END;

  FUNCTION GET_OHQTY(P_INV_ITEM_ID       IN VARCHAR2,
                     P_ORG_ID            NUMBER,
                     P_SUBINVENTORY_CODE IN VARCHAR2,
                     P_LOT_NUMBER        IN VARCHAR2,
                     P_QTY_TYPE          IN VARCHAR2) RETURN NUMBER IS
    X_RETURN_STATUS       VARCHAR2(50);
    X_MSG_COUNT           VARCHAR2(50);
    X_MSG_DATA            VARCHAR2(50);
    V_ITEM_ID             NUMBER;
    V_ORGANIZATION_ID     NUMBER;
    V_QOH                 NUMBER;
    V_RQOH                NUMBER;
    V_ATR                 NUMBER;
    V_ATT                 NUMBER;
    V_QR                  NUMBER;
    V_QS                  NUMBER;
    V_LOT_CONTROL_CODE    BOOLEAN;
    V_SERIAL_CONTROL_CODE BOOLEAN;
    L_QTY                 NUMBER;
  BEGIN
    SELECT INVENTORY_ITEM_ID, MP.ORGANIZATION_ID
      INTO V_ITEM_ID, V_ORGANIZATION_ID
      FROM MTL_SYSTEM_ITEMS_B MSIB, MTL_PARAMETERS MP
     WHERE MSIB.INVENTORY_ITEM_ID = P_INV_ITEM_ID
       AND MSIB.ORGANIZATION_ID = MP.ORGANIZATION_ID
       AND MSIB.ORGANIZATION_ID = P_ORG_ID; -- :ORGANIZATION_CODE;
  
    V_QOH              := NULL;
    V_RQOH             := NULL;
    V_ATR              := NULL;
    V_LOT_CONTROL_CODE := TRUE;
    --V_SERIAL_CONTROL_CODE := FALSE;
  
    -- FND_CLIENT_INFO.SET_ORG_CONTEXT (1);
    INV_QUANTITY_TREE_GRP.CLEAR_QUANTITY_CACHE;
    INV_QUANTITY_TREE_PUB.QUERY_QUANTITIES(P_API_VERSION_NUMBER  => 1.0,
                                           P_INIT_MSG_LST        => 'F',
                                           X_RETURN_STATUS       => X_RETURN_STATUS,
                                           X_MSG_COUNT           => X_MSG_COUNT,
                                           X_MSG_DATA            => X_MSG_DATA,
                                           P_ORGANIZATION_ID     => V_ORGANIZATION_ID,
                                           P_INVENTORY_ITEM_ID   => V_ITEM_ID,
                                           P_TREE_MODE           => APPS.INV_QUANTITY_TREE_PUB.G_TRANSACTION_MODE,
                                           P_IS_REVISION_CONTROL => NULL,
                                           P_IS_LOT_CONTROL      => V_LOT_CONTROL_CODE,
                                           P_IS_SERIAL_CONTROL   => NULL, --V_SERIAL_CONTROL_CODE,
                                           P_REVISION            => NULL, -- P_REVISION,
                                           P_LOT_NUMBER          => P_LOT_NUMBER,
                                           P_LOT_EXPIRATION_DATE => SYSDATE,
                                           P_SUBINVENTORY_CODE   => P_SUBINVENTORY_CODE,
                                           P_LOCATOR_ID          => NULL, -- P_LOCATOR_ID,
                                           P_ONHAND_SOURCE       => 3,
                                           X_QOH                 => V_QOH, -- QUANTITY ON-HAND
                                           X_RQOH                => V_RQOH,
                                           --RESERVABLE QUANTITY ON-HAND
                                           X_QR  => V_QR,
                                           X_QS  => V_QS,
                                           X_ATT => V_ATT, -- AVAILABLE TO TRANSACT
                                           X_ATR => V_ATR -- AVAILABLE TO RESERVE
                                           );
  
    IF P_QTY_TYPE = 'OHQ' THEN
      --ON HAND QTY
      L_QTY := V_QOH; --V_QUANTITYONHAND;
    ELSE
      IF P_QTY_TYPE = 'ATR' THEN
        --AVAILABLE TO RESERVE
        L_QTY := V_ATR;
      ELSE
        IF P_QTY_TYPE = 'ATT' THEN
          --AVAILABLE TO TRANSACT
          L_QTY := V_ATT;
        END IF;
      END IF;
    END IF;
  
    RETURN L_QTY;
    --RETURN V_ATR;
    PRINT_LOG('On-Hand Quantity: ' || V_QOH);
    PRINT_LOG('Available to reserve: ' || V_ATR);
    PRINT_LOG('Quantity Reserved: ' || V_QR);
    PRINT_LOG('Quantity Suggested: ' || V_QS);
    PRINT_LOG('Available to Transact: ' || V_ATT);
    PRINT_LOG('Available to Reserve: ' || V_ATR);
  EXCEPTION
    WHEN OTHERS THEN
      PRINT_LOG('ERROR: ' || SQLERRM);
      RETURN NULL; -------ADDED BY MAHIPAL YADAV ON 04-APR-2024
  END GET_OHQTY;

  PROCEDURE START_WORKFLOW(P_ORGANIZATION_ID NUMBER,
                           P_LRN_NUMBER      VARCHAR2,
                           P_SUBMITTER_ID    NUMBER,
                           P_LRN_STATUS      VARCHAR2) IS
    L_ITEMKEY  VARCHAR2(20) := P_LRN_NUMBER;
    L_ITEMTYPE VARCHAR2(240) := 'MSSLLRN';
    FROM_ROLE  VARCHAR2(100);
  BEGIN
    UPDATE XXMSSL.XXMSSL_LRN_HEADER_T
       SET ITEM_KEY = P_LRN_NUMBER, ITEM_TYPE = L_ITEMTYPE
     WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
       AND LRN_NO = P_LRN_NUMBER;
  
    --COMMIT;
    SELECT USER_NAME
      INTO FROM_ROLE
      FROM FND_USER
     WHERE USER_ID = P_SUBMITTER_ID;
  
    WF_ENGINE.CREATEPROCESS(L_ITEMTYPE, L_ITEMKEY, 'MSSL_LRN_APPROVAL');
    WF_ENGINE.SETITEMUSERKEY(ITEMTYPE => L_ITEMTYPE,
                             ITEMKEY  => L_ITEMKEY,
                             USERKEY  => 'USERKEY: ' || P_LRN_NUMBER);
    WF_ENGINE.SETITEMOWNER(ITEMTYPE => L_ITEMTYPE,
                           ITEMKEY  => L_ITEMKEY,
                           OWNER    => FROM_ROLE);
    WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => L_ITEMTYPE,
                              ITEMKEY  => L_ITEMKEY,
                              ANAME    => 'ORGANIZATION_ID',
                              AVALUE   => P_ORGANIZATION_ID);
    WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => L_ITEMTYPE,
                              ITEMKEY  => L_ITEMKEY,
                              ANAME    => 'LRN_NO',
                              AVALUE   => P_LRN_NUMBER);
    WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => L_ITEMTYPE,
                              ITEMKEY  => L_ITEMKEY,
                              ANAME    => 'LRN_STATUS',
                              AVALUE   => P_LRN_STATUS);
    WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => L_ITEMTYPE,
                                ITEMKEY  => L_ITEMKEY,
                                ANAME    => 'SUBMITTER_USER_ID',
                                AVALUE   => P_SUBMITTER_ID);
    WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => L_ITEMTYPE,
                              ITEMKEY  => L_ITEMKEY,
                              ANAME    => 'SUBMITTER_USER_NAME',
                              AVALUE   => FROM_ROLE);
    WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => L_ITEMTYPE,
                              ITEMKEY  => L_ITEMKEY,
                              ANAME    => '#FROM_ROLE',
                              AVALUE   => FROM_ROLE);
    WF_ENGINE.STARTPROCESS(L_ITEMTYPE, L_ITEMKEY);
    --  COMMIT;
  END START_WORKFLOW;

  PROCEDURE GET_APPROVER(ITEMTYPE IN VARCHAR2,
                         ITEMKEY  IN VARCHAR2,
                         ACTID    IN NUMBER,
                         FUNCMODE IN VARCHAR2,
                         RESULT   IN OUT VARCHAR2) IS
    L_ORGANIZATION_ID NUMBER;
    L_LOOKUP_CODE     NUMBER;
    L_DESCRIPTION     VARCHAR2(50);
    L_APPROVAL_VALUE  NUMBER;
    L_USER_ID         NUMBER;
    L_LRN_STATUS      VARCHAR2(20);
    L_FROM_ROLE       VARCHAR2(50);
    L_FROM_ROLE_ID    NUMBER;
    L_APPROVER_LIST   VARCHAR2(500); ---ADDE BY SHIKHA
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_ORGANIZATION_ID := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'ORGANIZATION_ID');
      L_APPROVAL_VALUE  := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'APPROVER_LOOKUP_CODE');
      L_LRN_STATUS      := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'LRN_STATUS');
    
      BEGIN
        SELECT /*LRN_STATUS,*/
         LAST_UPDATED_BY
          INTO /*L_LRN_STATUS,*/ L_FROM_ROLE_ID
          FROM XXMSSL.XXMSSL_LRN_HEADER_T
         WHERE ORGANIZATION_ID = L_ORGANIZATION_ID
           AND LRN_NO = ITEMKEY;
      EXCEPTION
        WHEN OTHERS THEN
          --L_LRN_STATUS := NULL;
          L_FROM_ROLE := NULL;
      END;
    
      IF L_LRN_STATUS IN ( /*'NEW', */ 'SUBMIT') THEN
        BEGIN
          /*SELECT   LOOKUP_CODE, DESCRIPTION
              INTO L_LOOKUP_CODE, L_DESCRIPTION
              FROM FND_LOOKUP_VALUES FLV,
                   ORG_ORGANIZATION_DEFINITIONS OOD
             WHERE FLV.LOOKUP_TYPE = 'MSSL_LRN_APPROVAL_LIST'
               AND FLV.TAG = OOD.ORGANIZATION_CODE
               AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
               AND LOOKUP_CODE > NVL (L_APPROVAL_VALUE, 0)
               AND ROWNUM = 1
          ORDER BY LOOKUP_CODE;*/
          SELECT LOOKUP_CODE, DESCRIPTION
            INTO L_LOOKUP_CODE, L_DESCRIPTION
            FROM (SELECT LOOKUP_CODE, DESCRIPTION
                  --                           INTO L_LOOKUP_CODE, L_DESCRIPTION
                    FROM FND_LOOKUP_VALUES            FLV,
                         ORG_ORGANIZATION_DEFINITIONS OOD
                   WHERE FLV.LOOKUP_TYPE = 'MSSL_LRN_APPROVAL_LIST'
                     AND FLV.TAG = OOD.ORGANIZATION_CODE
                     AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                     AND LOOKUP_CODE > NVL(L_APPROVAL_VALUE, 0)
                   ORDER BY TO_NUMBER(LOOKUP_CODE))
           WHERE ROWNUM = 1;
        EXCEPTION
          WHEN OTHERS THEN
            L_LOOKUP_CODE := 0;
            L_DESCRIPTION := NULL;
        END;
      
        BEGIN
          SELECT USER_ID
            INTO L_USER_ID
            FROM FND_USER
           WHERE USER_NAME = L_DESCRIPTION;
        EXCEPTION
          WHEN OTHERS THEN
            L_USER_ID := NULL;
        END;
      
        BEGIN
          SELECT USER_NAME
            INTO L_FROM_ROLE
            FROM FND_USER
           WHERE USER_ID = L_FROM_ROLE_ID;
        EXCEPTION
          WHEN OTHERS THEN
            L_FROM_ROLE := NULL;
        END;
      
        -----ADDED BY SHIKHA AT 19-AUG-14 ----
        BEGIN
          FOR J IN (SELECT (SELECT (FIRST_NAME || '-' || EMPLOYEE_NUMBER)
                              FROM PER_ALL_PEOPLE_F
                             WHERE PERSON_ID IN
                                   (SELECT EMPLOYEE_ID
                                      FROM FND_USER
                                     WHERE USER_NAME = XX.DESCRIPTION)
                               AND TRUNC(SYSDATE) BETWEEN
                                   EFFECTIVE_START_DATE AND
                                   EFFECTIVE_END_DATE
                               AND CURRENT_EMPLOYEE_FLAG = 'Y') APPROVER_NAME
                      FROM (SELECT DESCRIPTION
                              FROM FND_LOOKUP_VALUES            FLV,
                                   ORG_ORGANIZATION_DEFINITIONS OOD
                             WHERE FLV.LOOKUP_TYPE = 'MSSL_LRN_APPROVAL_LIST'
                               AND FLV.TAG = OOD.ORGANIZATION_CODE
                               AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                             ORDER BY LOOKUP_CODE) XX) LOOP
            IF L_APPROVER_LIST IS NULL THEN
              L_APPROVER_LIST := J.APPROVER_NAME;
            ELSE
              L_APPROVER_LIST := L_APPROVER_LIST || ' , ' ||
                                 J.APPROVER_NAME;
            END IF;
          END LOOP;
        EXCEPTION
          WHEN OTHERS THEN
            L_APPROVER_LIST := NULL;
        END;
      
        ----ENDED BY SHIKHA -----------
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => '#FROM_ROLE',
                                  AVALUE   => L_FROM_ROLE);
        WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'APPROVER_LOOKUP_CODE',
                                    AVALUE   => L_LOOKUP_CODE);
        WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'APPROVER_USER_ID',
                                    AVALUE   => L_USER_ID);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'APPROVER_USER_NAME',
                                  AVALUE   => L_DESCRIPTION);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'LRN_STATUS',
                                  AVALUE   => L_LRN_STATUS);
        -----ADDED BY SHIKHA
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'APPROVER_LIST',
                                  AVALUE   => L_APPROVER_LIST);
        ------ENDED
        --  COMMIT;
        RESULT := 'COMPLETE:Y';
      ELSIF L_LRN_STATUS NOT IN ( /*'NEW',*/ 'SUBMIT') THEN
        RESULT := WF_ENGINE.ENG_WAITING;
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG', 'GET_APPROVER', SQLERRM);
      RAISE;
  END GET_APPROVER;

  PROCEDURE CHECK_APPROVER_EXISTS(ITEMTYPE IN VARCHAR2,
                                  ITEMKEY  IN VARCHAR2,
                                  ACTID    IN NUMBER,
                                  FUNCMODE IN VARCHAR2,
                                  RESULT   IN OUT VARCHAR2) IS
    L_ORGANIZATION_ID NUMBER;
    L_LOOKUP_CODE     NUMBER;
    L_DESCRIPTION     VARCHAR2(50);
    L_APPROVAL_VALUE  NUMBER;
    L_USER_ID         NUMBER;
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_ORGANIZATION_ID := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'ORGANIZATION_ID');
      L_APPROVAL_VALUE  := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'APPROVER_LOOKUP_CODE');
    
      BEGIN
        SELECT LOOKUP_CODE, DESCRIPTION
          INTO L_LOOKUP_CODE, L_DESCRIPTION
          FROM (SELECT LOOKUP_CODE, DESCRIPTION
                --                INTO L_LOOKUP_CODE, L_DESCRIPTION
                  FROM FND_LOOKUP_VALUES            FLV,
                       ORG_ORGANIZATION_DEFINITIONS OOD
                 WHERE FLV.LOOKUP_TYPE = 'MSSL_LRN_APPROVAL_LIST'
                   AND FLV.TAG = OOD.ORGANIZATION_CODE
                   AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                   AND LOOKUP_CODE > NVL(L_APPROVAL_VALUE, 0)
                 ORDER BY TO_NUMBER(LOOKUP_CODE))
         WHERE ROWNUM = 1;
      EXCEPTION
        WHEN OTHERS THEN
          L_LOOKUP_CODE := 0;
          L_DESCRIPTION := NULL;
      END;
    
      IF L_LOOKUP_CODE > 0 THEN
        BEGIN
          SELECT USER_ID
            INTO L_USER_ID
            FROM FND_USER
           WHERE USER_NAME = L_DESCRIPTION;
        EXCEPTION
          WHEN OTHERS THEN
            L_USER_ID := NULL;
        END;
      
        WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'APPROVER_LOOKUP_CODE',
                                    AVALUE   => L_LOOKUP_CODE);
        WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'APPROVER_USER_ID',
                                    AVALUE   => L_USER_ID);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'APPROVER_USER_NAME',
                                  AVALUE   => L_DESCRIPTION);
        RESULT := 'COMPLETE:Y';
      ELSIF L_LOOKUP_CODE = 0 THEN
        RESULT := 'COMPLETE:N';
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG', 'CHECK_APPROVER_EXISTS', SQLERRM);
      RAISE;
  END CHECK_APPROVER_EXISTS;

  PROCEDURE UPDATE_LRN_STATUS(ITEMTYPE IN VARCHAR2,
                              ITEMKEY  IN VARCHAR2,
                              ACTID    IN NUMBER,
                              FUNCMODE IN VARCHAR2,
                              RESULT   IN OUT VARCHAR2) IS
    L_ORGANIZATION_ID   NUMBER;
    L_LRN_STATUS        VARCHAR2(20);
    L_APPROVER_ID       NUMBER;
    L_USER_NAME         VARCHAR2(50);
    L_REQUEST_ID        NUMBER;
    L_ROLE_USERS        VARCHAR2(500);
    L_AFTER_APPROVAL    VARCHAR2(500);
    L_MOVE_ORDER_NUMBER VARCHAR2(20);
    LC_PHASE            VARCHAR2(50);
    LC_STATUS           VARCHAR2(50);
    LC_DEV_PHASE        VARCHAR2(50);
    LC_DEV_STATUS       VARCHAR2(50);
    LC_MESSAGE          VARCHAR2(50);
    L_REQ_RETURN_STATUS BOOLEAN;
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_ORGANIZATION_ID := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'ORGANIZATION_ID');
      L_LRN_STATUS      := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'LRN_STATUS');
    
      --       XXMSSL_PRAGMA_TEST(1,L_ORGANIZATION_ID);
      --       XXMSSL_PRAGMA_TEST(1,ITEMKEY);
      --       XXMSSL_PRAGMA_TEST(1,ITEMTYPE);
      BEGIN
        SELECT LAST_UPDATED_BY
          INTO L_APPROVER_ID
          FROM XXMSSL.XXMSSL_LRN_HEADER_T
         WHERE ORGANIZATION_ID = L_ORGANIZATION_ID
           AND LRN_NO = ITEMKEY;
      EXCEPTION
        WHEN OTHERS THEN
          L_APPROVER_ID := NULL;
      END;
    
      BEGIN
        SELECT USER_NAME
          INTO L_USER_NAME
          FROM FND_USER
         WHERE USER_ID = L_APPROVER_ID;
      EXCEPTION
        WHEN OTHERS THEN
          L_USER_NAME := NULL;
      END;
    
      -----ADDED BY SHIKHA AT 19-AUG-14 ----
      BEGIN
        FOR J IN (SELECT (SELECT (FIRST_NAME || '-' || EMPLOYEE_NUMBER)
                            FROM PER_ALL_PEOPLE_F
                           WHERE PERSON_ID IN
                                 (SELECT EMPLOYEE_ID
                                    FROM FND_USER
                                   WHERE USER_NAME = XX.DESCRIPTION)
                             AND TRUNC(SYSDATE) BETWEEN EFFECTIVE_START_DATE AND
                                 EFFECTIVE_END_DATE
                             AND CURRENT_EMPLOYEE_FLAG = 'Y') APPROVER_NAME
                    FROM (SELECT DESCRIPTION
                            FROM FND_LOOKUP_VALUES            FLV,
                                 ORG_ORGANIZATION_DEFINITIONS OOD
                           WHERE FLV.LOOKUP_TYPE =
                                 'XXMSSL_LRN_AFTER_APPROVAL_LIST'
                             AND FLV.TAG = OOD.ORGANIZATION_CODE
                             AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                             AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                                 TRUNC(SYSDATE)
                             AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >=
                                 TRUNC(SYSDATE)
                          UNION
                          SELECT USER_NAME
                            FROM XXMSSL_LRN_HEADER_T XX, FND_USER FU
                           WHERE XX.LAST_UPDATED_BY = FU.USER_ID
                             AND LRN_NO = ITEMKEY) XX) LOOP
          IF L_AFTER_APPROVAL IS NULL THEN
            L_AFTER_APPROVAL := J.APPROVER_NAME;
          ELSE
            L_AFTER_APPROVAL := L_AFTER_APPROVAL || ' , ' ||
                                J.APPROVER_NAME;
          END IF;
        END LOOP;
      EXCEPTION
        WHEN OTHERS THEN
          L_AFTER_APPROVAL := NULL;
      END;
    
      ----ENDED BY SHIKHA -----------
      IF L_LRN_STATUS = 'APPROVE' THEN
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => '#FROM_ROLE',
                                  AVALUE   => L_USER_NAME);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'LRN_STATUS',
                                  AVALUE   => L_LRN_STATUS);
        UPDATE_LRN_ATTRIBUTE(L_ORGANIZATION_ID, ITEMKEY);
        L_REQUEST_ID := FND_REQUEST.SUBMIT_REQUEST(APPLICATION => 'XXMSSL',
                                                   PROGRAM     => 'XXMSSL_LRN_CREATE_TRANS',
                                                   DESCRIPTION => 'XXMSSL: LRN Subinventory and Move Order Transfer',
                                                   START_TIME  => NULL,
                                                   SUB_REQUEST => NULL,
                                                   ARGUMENT1   => L_ORGANIZATION_ID,
                                                   ARGUMENT2   => ITEMKEY);
      
        IF L_REQUEST_ID IS NOT NULL THEN
          COMMIT;
          -- WAIT FOR REQUEST TO FINISH
          L_REQ_RETURN_STATUS := FND_CONCURRENT.WAIT_FOR_REQUEST(REQUEST_ID => L_REQUEST_ID,
                                                                 INTERVAL   => 30,
                                                                 MAX_WAIT   => 120,
                                                                 PHASE      => LC_PHASE,
                                                                 STATUS     => LC_STATUS,
                                                                 DEV_PHASE  => LC_DEV_PHASE,
                                                                 DEV_STATUS => LC_DEV_STATUS,
                                                                 MESSAGE    => LC_MESSAGE);
        END IF;
      
        BEGIN
          SELECT MOVE_ORDER_NUMBER
            INTO L_MOVE_ORDER_NUMBER
            FROM XXMSSL_LRN_HEADER_T T
           WHERE T.MOVE_ORDER_NUMBER IS NOT NULL
             AND LRN_NO = ITEMKEY
             AND ITEM_KEY = ITEMKEY
             AND ITEM_TYPE = ITEMTYPE
             AND ORGANIZATION_ID = L_ORGANIZATION_ID;
        EXCEPTION
          WHEN OTHERS THEN
            L_MOVE_ORDER_NUMBER := NULL;
        END;
      
        -- WF_ENGINE.ADDITEMATTR(ITEMTYPE, ITEMKEY, 'MOVE_ORDER');
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'MOVE_ORDER',
                                  AVALUE   => L_MOVE_ORDER_NUMBER);
        -----ADDED BY SHIKHA
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'APPROVER_LIST',
                                  AVALUE   => L_AFTER_APPROVAL);
        ------ENDED
        -- COMMIT;
        RESULT := 'COMPLETE:Y';
        RETURN;
      ELSIF L_LRN_STATUS = 'REJECT' THEN
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => '#FROM_ROLE',
                                  AVALUE   => L_USER_NAME);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'LRN_STATUS',
                                  AVALUE   => L_LRN_STATUS);
        RESULT := 'COMPLETE:Y';
        RETURN;
      ELSIF L_LRN_STATUS = 'RETURN TO CREATOR' THEN
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => '#FROM_ROLE',
                                  AVALUE   => L_USER_NAME);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'LRN_STATUS',
                                  AVALUE   => L_LRN_STATUS);
        RESULT := 'COMPLETE:N';
        RETURN;
      ELSIF L_LRN_STATUS NOT IN ('APPROVE', 'REJECT', 'RETURN TO CREATOR') THEN
        RESULT := WF_ENGINE.ENG_WAITING;
        RETURN;
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG', 'UPDATE_LRN_STATUS', SQLERRM);
      RAISE;
  END UPDATE_LRN_STATUS;

  PROCEDURE CHECK_RETURN_TO_CREATOR(ITEMTYPE IN VARCHAR2,
                                    ITEMKEY  IN VARCHAR2,
                                    ACTID    IN NUMBER,
                                    FUNCMODE IN VARCHAR2,
                                    RESULT   IN OUT VARCHAR2) IS
    L_COUNT           NUMBER;
    L_ORGANIZATION_ID NUMBER;
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_ORGANIZATION_ID := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'ORGANIZATION_ID');
    
      SELECT COUNT(*)
        INTO L_COUNT
        FROM XXMSSL.XXMSSL_LRN_HEADER_T
       WHERE ORGANIZATION_ID = L_ORGANIZATION_ID
         AND LRN_NO = ITEMKEY
         AND LRN_STATUS = 'RETURN TO CREATOR';
    
      IF L_COUNT > 0 THEN
        WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'APPROVER_LOOKUP_CODE',
                                    AVALUE   => NULL);
        RESULT := 'COMPLETE:Y';
      ELSIF L_COUNT = 0 THEN
        RESULT := 'COMPLETE:N';
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG', 'CHECK_RETURN_TO_CREATOR', SQLERRM);
      RAISE;
  END CHECK_RETURN_TO_CREATOR;

  PROCEDURE LRN_DETAILS(L_LRN_NUMBER  IN VARCHAR2,
                        DISPLAY_TYPE  IN VARCHAR2,
                        DOCUMENT      IN OUT NOCOPY VARCHAR2,
                        DOCUMENT_TYPE IN OUT NOCOPY VARCHAR2) IS
    --L_LRN_DETAILS       CLOB;
    L_LRN_NO            VARCHAR2(20);
    L_LRN_STATUS        VARCHAR2(30);
    L_REMARKS           VARCHAR2(4000);
    L_CREATION_DATE     VARCHAR2(20);
    L_LAST_UPDATE_DATE  VARCHAR2(20);
    L_CREATED_BY        VARCHAR2(50);
    L_LAST_UPDATED_BY   VARCHAR2(50);
    L_LRN_HEADER        VARCHAR2(4000);
    L_LRN_DETAIL_HEADER VARCHAR2(4000);
    L_LRN_DETAIL_VALUES VARCHAR2(32000);
    L_VALUE             NUMBER := 0;
  
    CURSOR C_DETAILS IS
      SELECT LRN_NO,
             DECODE(JOB_ITEM_FLAG, 'I', 'Item', 'J', 'Job') JOB_ITEM_FLAG,
             LINE_NUM,
             NVL(JOB_NUMBER, ';') JOB_NUMBER,
             ITEM_CODE,
             ITEM_DESCRIPTION,
             UOM,
             SUBINVENTORY_CODE,
             SUBINVENTORY_QTY,
             NVL(TO_CHAR(JOB_QUANTITY), ';') JOB_QUANTITY,
             LRN_QUANTITY,
             LRN_REASON_CODE,
             LRN_TYPE,
             ROUND(AVERAGE_COST, 4) AVERAGE_COST,
             ROUND(VALUE, 4) VALUE
        FROM XXMSSL_LRN_DETAIL_T
       WHERE LRN_NO = L_LRN_NUMBER;
  BEGIN
    SELECT LRN_NO,
           LRN_STATUS,
           NVL(REMARKS, ';') REMARKS,
           TO_CHAR(CREATION_DATE, 'DD-MON-RRRR HH24:MI:SS'),
           TO_CHAR(LAST_UPDATE_DATE, 'DD-MON-RRRR HH24:MI:SS'),
           (SELECT USER_NAME
              FROM FND_USER FU
             WHERE FU.USER_ID = XLH.CREATED_BY),
           (SELECT USER_NAME
              FROM FND_USER FU
             WHERE FU.USER_ID = XLH.LAST_UPDATED_BY),
           ROUND(LRN_VALUE, 4) LRN_VALUE
      INTO L_LRN_NO,
           L_LRN_STATUS,
           L_REMARKS,
           L_CREATION_DATE,
           L_LAST_UPDATE_DATE,
           L_CREATED_BY,
           L_LAST_UPDATED_BY,
           L_VALUE
      FROM XXMSSL.XXMSSL_LRN_HEADER_T XLH
     WHERE LRN_NO = L_LRN_NUMBER;
  
    FOR V_DETAILS IN C_DETAILS LOOP
      NULL;
    END LOOP;
  
    L_LRN_HEADER := '<b>LRN Header </b><br><TABLE cellpadding = 1 , border=1>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>LRN Number</b></td><td><font size="3">' ||
                    TO_CHAR(L_LRN_NO) || '</td></tr>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>LRN Status</b></td><td><font size="3">' ||
                    L_LRN_STATUS || '</td></tr>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>Remarks</b></td><td><font size="3">' ||
                    L_REMARKS || '</td></tr>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>Created By</b></td><td><font size="3">' ||
                    L_CREATED_BY || '</td></tr>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>Creation Date</b></td><td><font size="3">' ||
                    L_CREATION_DATE || '</td></tr>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>Status Change Date</b></td><td><font size="3">' ||
                    L_LAST_UPDATE_DATE || '</td></tr>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>Status Changed By</b></td><td><font size="3">' ||
                    L_LAST_UPDATED_BY || '</td></tr>' ||
                    '<tr><td bgcolor = #CCCCCC><font size="3"><b>LRN VALUE</b></td><td><font size="3">' ||
                    L_VALUE || '</td></tr></TABLE>';
    /*ADDED BY HIMANSHU BANSAL ADDITIONAL FIELD AS PER REQUIREMENT */
    L_LRN_DETAIL_HEADER := '<b>LRN Details </b><table border="1">
           <tr>
            <th bgcolor = #CCCCCC>LRN No.</th>
            <th bgcolor = #CCCCCC>Job/Item </th>
            <th bgcolor = #CCCCCC>S.No.</th>
            <th bgcolor = #CCCCCC>Job Number</th>
            <th bgcolor = #CCCCCC>Item Code</th>
            <th bgcolor = #CCCCCC>Average Cost</th>
            <th bgcolor = #CCCCCC>Item Description</th>
            <th bgcolor = #CCCCCC>UOM</th>
            <th bgcolor = #CCCCCC>Location</th>
            <th bgcolor = #CCCCCC>Location Qty</th>
             <th bgcolor = #CCCCCC>LRN VALUE</th>
            <th bgcolor = #CCCCCC>Job Qty</th>
            <th bgcolor = #CCCCCC>LRN Qty</th>
            <th bgcolor = #CCCCCC>LRN Reason</th>
            <th bgcolor = #CCCCCC>LRN Type</th>
            </tr>';
  
    FOR V_DETAILS IN C_DETAILS LOOP
      L_LRN_DETAIL_VALUES := L_LRN_DETAIL_VALUES || '<tr><td>' ||
                             V_DETAILS.LRN_NO || '</td><td>' ||
                             V_DETAILS.JOB_ITEM_FLAG || '</td><td>' ||
                             V_DETAILS.LINE_NUM || '</td><td align=right>' ||
                             V_DETAILS.JOB_NUMBER || '</td><td>' ||
                             V_DETAILS.ITEM_CODE || '</td><td>' ||
                             V_DETAILS.AVERAGE_COST
                            /*ADDED BY HIMANSHU BANSAL ADDITIONAL FIELD AS PER REQUIREMENT */
                             || '</td><td>' || V_DETAILS.ITEM_DESCRIPTION ||
                             '</td><td>' || V_DETAILS.UOM || '</td><td>' ||
                             V_DETAILS.SUBINVENTORY_CODE || '</td><td>' ||
                             V_DETAILS.SUBINVENTORY_QTY ||
                             '</td><td align=right>'
                            /*ADDED BY HIMANSHU BANSAL ADDITIONAL FIELD AS PER REQUIREMENT */
                             || V_DETAILS.VALUE || '</td><td align=right>' ||
                             V_DETAILS.JOB_QUANTITY ||
                             '</td><td align=right>' ||
                             V_DETAILS.LRN_QUANTITY ||
                             '</td><td align=right>' ||
                             V_DETAILS.LRN_REASON_CODE || '</td><td>' ||
                             V_DETAILS.LRN_TYPE || '</td></tr>';
    END LOOP;
  
    DOCUMENT := '<br>' || L_LRN_HEADER || '<br><br>' || L_LRN_DETAIL_HEADER ||
                L_LRN_DETAIL_VALUES;
  END LRN_DETAILS;

  PROCEDURE UPDATE_LRN_ATTRIBUTE(P_ORGANIZATION_ID IN NUMBER,
                                 P_LRN_NUMBER      IN VARCHAR2) IS
    CURSOR C1 IS
      SELECT *
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND LRN_NO = P_LRN_NUMBER
         AND JOB_ITEM_FLAG = 'J';
  BEGIN
    FOR V1 IN C1 LOOP
      UPDATE WIP_REQUIREMENT_OPERATIONS
         SET ATTRIBUTE3 = NVL(ATTRIBUTE3, 0) + V1.LRN_QUANTITY
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND WIP_ENTITY_ID = V1.WIP_ENTITY_ID
         AND INVENTORY_ITEM_ID = V1.INVENTORY_ITEM_ID;
    END LOOP;
    --COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END UPDATE_LRN_ATTRIBUTE;

  PROCEDURE CREATE_INV_TRANSACTION(ERRBUF            OUT VARCHAR2,
                                   RETCODE           OUT NUMBER,
                                   P_ORGANIZATION_ID IN NUMBER,
                                   P_LRN_NUMBER      IN VARCHAR2) IS
    L_COUNT           NUMBER;
    L_TO_SUBINVENTORY VARCHAR2(10);
  BEGIN
    ---------COMMENT BY YASHWANT ON 05-JUN-2019  FOR NO REQUIRED SUB INV TRANSFER AT APPROVAL TIME------------------
    --SUBINVENTORY_TRANSFER (P_ORGANIZATION_ID, P_LRN_NUMBER); COMMENT BY YASHWANT ON 05-JUN-2019 AS PER CHANAGE REQUIRED BY BHUPESH
    ------------COMMENT BY YASHWANT ON 05-JUN-2019  FOR NO REQUIRED SUB INV TRANSFER AT APPROVAL TIME------------------
  
    /********************* WIP SUBINVENTORY VALIDATION *******************/
    BEGIN
      SELECT MSI.SECONDARY_INVENTORY_NAME
        INTO L_TO_SUBINVENTORY
        FROM FND_LOOKUP_VALUES            FLV,
             ORG_ORGANIZATION_DEFINITIONS OOD,
             MTL_SECONDARY_INVENTORIES    MSI
       WHERE LOOKUP_TYPE = 'XXMSSL_LRN_SUBINVENTORY_TRF'
         AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
         AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
         AND FLV.ENABLED_FLAG = 'Y'
         AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE)
         AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
         AND ROWNUM = 1;
    EXCEPTION
      WHEN OTHERS THEN
        L_TO_SUBINVENTORY := NULL;
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Error : No Subinventory Defined in lookup ''XXMSSL_LRN_SUBINVENTORY_TRF'' For Subinventory Transfer');
        RETURN;
    END;
  
    SELECT COUNT(*)
      INTO L_COUNT
      FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD, XXMSSL.XXMSSL_LRN_HEADER_T XLH
     WHERE XLD.ORGANIZATION_ID = XLH.ORGANIZATION_ID
       AND XLD.LRN_NO = XLH.LRN_NO
       AND XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
       AND XLD.LRN_NO = P_LRN_NUMBER
       AND XLH.LRN_STATUS IN( 'APPROVE','COMPLETE')
       AND NVL(XLD.MOVE_ORDER_TRANSFER, 'N') = 'N'
       AND SUBINVENTORY_TRANSFER = 'Y'
       AND ((JOB_ITEM_FLAG = 'J') OR
           (JOB_ITEM_FLAG = 'I' AND SUBINVENTORY_CODE = L_TO_SUBINVENTORY));
  
    IF L_COUNT > 0 THEN
      MOVE_ORDER_TRANSFER(P_ORGANIZATION_ID, P_LRN_NUMBER);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'EXCEPTION :' || SQLERRM);
      ERRBUF  := 'Error :' || SQLERRM;
      RETCODE := 2;
  END;
----v 1.6   package is obsolet and no longer uses 
  PROCEDURE SUBINVENTORY_TRANSFER(P_ORGANIZATION_ID IN NUMBER,
                                  P_LRN_NUMBER      IN VARCHAR2,
                                  P_RET_STATUS      OUT VARCHAR2,
                                  P_RET_MSG         OUT VARCHAR2) IS
    L_USER_ID                  NUMBER := FND_PROFILE.VALUE('USER_ID');
    L_LOGIN_ID                 NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
    L_TRANSACTION_INTERFACE_ID NUMBER;
    V_RET_VAL                  NUMBER;
    L_RETURN_STATUS            VARCHAR2(100);
    L_MSG_CNT                  NUMBER;
    L_MSG_DATA                 VARCHAR2(4000);
    L_TRANS_COUNT              NUMBER;
    X_MSG_INDEX                NUMBER;
    X_MSG                      VARCHAR2(4000);
    L_TO_SUBINVENTORY          VARCHAR2(50);
    L_COUNT                    NUMBER;
    L_TRANSACTION_TYPE_ID      NUMBER;
    L_TRANSACTION_QUANTITY     NUMBER;
    L_REMAINING_QUANTITY       NUMBER;
    LC_ORG_ID                  NUMBER := FND_PROFILE.VALUE('ORG_ID');
    L_OU                       NUMBER;
    L_ONHAND_QTY               NUMBER;
  
    -----ADD BY GAUTAM KUMAR ON 8-FEB-2021
    CURSOR C1 IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD, XXMSSL.XXMSSL_LRN_HEADER_T XLH
       WHERE XLD.ORGANIZATION_ID = XLH.ORGANIZATION_ID
         AND XLD.LRN_NO = XLH.LRN_NO
         AND XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
            --AND XLH.LRN_STATUS = 'APPROVE'
         AND NVL(XLD.SUBINVENTORY_TRANSFER, 'N') IN ('N', 'R') --R IS ADDED BY YASHWANT ON 05-DEC-2019
         AND XLH.TRANSACTION_TYPE = 'LRN';
  
    --ADDED BY DALJEET ON 25-NOV-2020 FOR IDACS
    CURSOR C_LOT(P_INVENTORY_ITEM_ID NUMBER,
                 P_SUBINVENTORY_CODE IN VARCHAR2) IS
      SELECT *
        FROM (SELECT MLN.LOT_NUMBER,
                     MLN.CREATION_DATE,
                     XXMSSL_LRN_PKG.GET_OHQTY(MOQ.INVENTORY_ITEM_ID,
                                              MOQ.ORGANIZATION_ID,
                                              MOQ.SUBINVENTORY_CODE,
                                              MLN.LOT_NUMBER,
                                              'ATT') TRANSACTION_QUANTITY
                FROM MTL_ONHAND_QUANTITIES MOQ, MTL_LOT_NUMBERS MLN
               WHERE MOQ.ORGANIZATION_ID = MLN.ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
                 AND MLN.LOT_NUMBER = MOQ.LOT_NUMBER
                 AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
                 AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
               GROUP BY MLN.LOT_NUMBER,
                        MOQ.INVENTORY_ITEM_ID,
                        MOQ.ORGANIZATION_ID,
                        SUBINVENTORY_CODE,
                        MLN.CREATION_DATE)
       WHERE TRANSACTION_QUANTITY > 0
       ORDER BY CREATION_DATE;
  BEGIN
    G_LRN_NO := P_LRN_NUMBER;
    G_ACTION := 'SUBINVENTORY_TRANSFER';
    PRINT_LOG('<----------- Starting Subinventory Transfer Process ------------>');
    PRINT_LOG('LRN No: ' || P_LRN_NUMBER);
    PRINT_LOG('p_organization_id : ' || P_ORGANIZATION_ID);
   -- PRINT_LOG('Start delete from xxmssl_lrn_subinv_lot ');
  
    DELETE FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT
     WHERE LRN_NO = P_LRN_NUMBER
       AND ORGANIZATION_ID = P_ORGANIZATION_ID;
  
    PRINT_LOG('end delete from xxmssl_lrn_subinv_lot ');
    PRINT_LOG('start get transaction type');
  
    /**************** GET TRANSACTION TYPE ***************************/
    BEGIN
      SELECT TRANSACTION_TYPE_ID
        INTO L_TRANSACTION_TYPE_ID
        FROM MTL_TRANSACTION_TYPES
       WHERE TRANSACTION_TYPE_NAME = 'LRN Transfers'
         AND TRANSACTION_SOURCE_TYPE_ID = 13;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRANSACTION_TYPE_ID := NULL;
    END;
  
    PRINT_LOG('l_transaction_type_id :- ' || L_TRANSACTION_TYPE_ID);
    PRINT_LOG('end get transaction type');
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'Transaction Type ''LRN Transfers'' is not Defined';
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Transaction Type ''LRN Transfers'' is not Defined');
      RETURN;
    END IF;
  
    /**************************** CHECK PERIOD IS OPEN ****************/
    PRINT_LOG('start check period ');
  
    SELECT COUNT(*)
      INTO L_COUNT
      FROM ORG_ACCT_PERIODS_V
     WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
       AND TRUNC(SYSDATE) BETWEEN START_DATE AND END_DATE
       AND UPPER(STATUS) = 'OPEN';
  
    IF L_COUNT = 0 THEN
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'Period is Not Open';
      PRINT_LOG('Period is Not Open');
      RETURN;
    END IF;
  
    PRINT_LOG('end check period ');
  
    BEGIN
      SELECT OPERATING_UNIT
        INTO L_OU
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_OU := NULL;
    END;
  
    PRINT_LOG('l_ou :- ' || L_OU);
    MO_GLOBAL.SET_POLICY_CONTEXT('S', L_OU);
    INV_GLOBALS.SET_ORG_ID(P_ORGANIZATION_ID);
    MO_GLOBAL.INIT('INV');
  
    /********************* TO SUBINVENTORY *******************/
    BEGIN
      SELECT MSI.SECONDARY_INVENTORY_NAME
        INTO L_TO_SUBINVENTORY
        FROM FND_LOOKUP_VALUES            FLV,
             ORG_ORGANIZATION_DEFINITIONS OOD,
             MTL_SECONDARY_INVENTORIES    MSI
       WHERE LOOKUP_TYPE = 'XXMSSL_LRN_MRB_SUBINVENTORY'
         AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
         AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
         AND FLV.ENABLED_FLAG = 'Y'
         AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE)
         AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
         AND ROWNUM = 1;
    EXCEPTION
      WHEN OTHERS THEN
        L_TO_SUBINVENTORY := NULL;
        P_RET_STATUS      := 'E';
        P_RET_MSG         := 'Error : No Subinventory Defined in lookup ''XXMSSL_LRN_MRB_SUBINVENTORY'' For Subinventory Transfer';
        PRINT_LOG('Error : No Subinventory Defined in lookup ''XXMSSL_LRN_MRB_SUBINVENTORY'' For Subinventory Transfer');
        RETURN;
    END;
  
    PRINT_LOG('l_to_subinventory :- ' || L_TO_SUBINVENTORY);
    PRINT_LOG('Strat Loop C1 :- ');
  
    FOR V1 IN C1 LOOP
      -------------------------------------------  ADD BY GAUTAM ON 8-FEB-2021
      SELECT XXMSSL_WIP_MOVE_ORDER_PKG.GET_ONHAND_QTY(V1.ORGANIZATION_ID,
                                                      V1.INVENTORY_ITEM_ID,
                                                      V1.SUBINVENTORY_CODE)
        INTO L_ONHAND_QTY
        FROM DUAL;
    
      IF L_ONHAND_QTY >= V1.LRN_QUANTITY THEN
        ----------------------------------------------------ADD BY GAUTAM ON 8-FEB-2021
        PRINT_LOG('inventory_item_id :- ' || V1.INVENTORY_ITEM_ID);
        PRINT_LOG('subinventory_code :- ' || V1.SUBINVENTORY_CODE);
        PRINT_LOG('lrn_quantity :- ' || V1.LRN_QUANTITY);
        L_RETURN_STATUS := NULL;
        L_MSG_CNT       := NULL;
        L_MSG_DATA      := NULL;
        L_TRANS_COUNT   := NULL;
      
        SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
          INTO L_TRANSACTION_INTERFACE_ID
          FROM DUAL;
      
        PRINT_LOG(' start insert into mtl_transactions_interface');
      
        INSERT INTO MTL_TRANSACTIONS_INTERFACE
          (CREATED_BY,
           CREATION_DATE,
           INVENTORY_ITEM_ID,
           LAST_UPDATED_BY,
           LAST_UPDATE_DATE,
           LAST_UPDATE_LOGIN,
           LOCK_FLAG,
           ORGANIZATION_ID,
           PROCESS_FLAG,
           SOURCE_CODE,
           SOURCE_HEADER_ID,
           SOURCE_LINE_ID,
           SUBINVENTORY_CODE,
           TRANSACTION_DATE,
           TRANSACTION_HEADER_ID,
           TRANSACTION_INTERFACE_ID,
           TRANSACTION_MODE,
           TRANSACTION_QUANTITY,
           TRANSACTION_TYPE_ID,
           TRANSACTION_UOM,
           TRANSFER_SUBINVENTORY,
           TRANSACTION_REFERENCE)
        VALUES
          (L_USER_ID,
           SYSDATE,
           V1.INVENTORY_ITEM_ID,
           L_USER_ID,
           SYSDATE,
           L_LOGIN_ID,
           2,
           P_ORGANIZATION_ID,
           1,
           'LRN Subinventory Transfer',
           1,
           2,
           V1.SUBINVENTORY_CODE,
           SYSDATE,
           L_TRANSACTION_INTERFACE_ID,
           L_TRANSACTION_INTERFACE_ID,
           3,
           V1.LRN_QUANTITY,
           L_TRANSACTION_TYPE_ID,
           V1.UOM,
           L_TO_SUBINVENTORY,
           P_LRN_NUMBER);
      
        /*FOR LOG PURPOSE */
        INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
          (CREATED_BY,
           CREATION_DATE,
           INVENTORY_ITEM_ID,
           LAST_UPDATED_BY,
           LAST_UPDATE_DATE,
           LAST_UPDATE_LOGIN,
           LOCK_FLAG,
           ORGANIZATION_ID,
           PROCESS_FLAG,
           SOURCE_CODE,
           SOURCE_HEADER_ID,
           SOURCE_LINE_ID,
           SUBINVENTORY_CODE,
           TRANSACTION_DATE,
           TRANSACTION_HEADER_ID,
           TRANSACTION_INTERFACE_ID,
           TRANSACTION_MODE,
           TRANSACTION_QUANTITY,
           TRANSACTION_TYPE_ID,
           TRANSACTION_UOM,
           TRANSFER_SUBINVENTORY,
           TRANSACTION_REFERENCE)
        VALUES
          (L_USER_ID,
           SYSDATE,
           V1.INVENTORY_ITEM_ID,
           L_USER_ID,
           SYSDATE,
           L_LOGIN_ID,
           2,
           P_ORGANIZATION_ID,
           1,
           'LRN Subinventory Transfer',
           1,
           2,
           V1.SUBINVENTORY_CODE,
           SYSDATE,
           L_TRANSACTION_INTERFACE_ID,
           L_TRANSACTION_INTERFACE_ID,
           3,
           V1.LRN_QUANTITY,
           L_TRANSACTION_TYPE_ID,
           V1.UOM,
           L_TO_SUBINVENTORY,
           P_LRN_NUMBER);
      
        PRINT_LOG(' end  insert into mtl_transactions_interface');
      
        /***************** CHECK ITEM IS LOT CONTROLLED ***************/
        SELECT COUNT(*)
          INTO L_COUNT
          FROM MTL_SYSTEM_ITEMS_B
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND INVENTORY_ITEM_ID = V1.INVENTORY_ITEM_ID
           AND LOT_CONTROL_CODE = 2;
      
        PRINT_LOG(' check item is lot control l_count = ' || L_COUNT);
      
        IF L_COUNT > 0 THEN
          L_REMAINING_QUANTITY := V1.LRN_QUANTITY;
          PRINT_LOG(' insert into lot loop l_remaining_quantity=  ' ||
                    L_REMAINING_QUANTITY);
        
          FOR V_LOT IN C_LOT(V1.INVENTORY_ITEM_ID, V1.SUBINVENTORY_CODE) LOOP
            L_TRANSACTION_QUANTITY := NULL;
            PRINT_LOG(' lot_quantity =  ' || V_LOT.TRANSACTION_QUANTITY);
            PRINT_LOG(' Lot no.  =  ' || V_LOT.LOT_NUMBER);
          
            IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
              L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
              L_REMAINING_QUANTITY   := 0;
            ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
              L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
              L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                        V_LOT.TRANSACTION_QUANTITY;
            END IF;
          
            PRINT_LOG(' l_remaining_quantity =  ' || L_REMAINING_QUANTITY);
            PRINT_LOG(' l_transaction_quantity  ' ||
                      L_TRANSACTION_QUANTITY);
            PRINT_LOG(' Insert into mtl_transaction_lots_interface  ');
          
            INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
              (TRANSACTION_INTERFACE_ID,
               LOT_NUMBER,
               TRANSACTION_QUANTITY,
               LAST_UPDATE_DATE,
               LAST_UPDATED_BY,
               CREATION_DATE,
               CREATED_BY)
            VALUES
              (L_TRANSACTION_INTERFACE_ID,
               V_LOT.LOT_NUMBER,
               L_TRANSACTION_QUANTITY,
               SYSDATE,
               L_USER_ID,
               SYSDATE,
               L_USER_ID);
          
            PRINT_LOG(' Insert into xxmssl_lrn_subinv_lot  ');
          
            INSERT INTO XXMSSL.XXMSSL_LRN_SUBINV_LOT
              (ORGANIZATION_ID,
               LRN_NO,
               INVENTORY_ITEM_ID,
               SUBINVENTORY_CODE,
               LOT_NUMBER,
               LOT_QUANTITY,
               CREATION_DATE,
               CREATED_BY,
               LINE_NUMBER)
            VALUES
              (P_ORGANIZATION_ID,
               P_LRN_NUMBER,
               V1.INVENTORY_ITEM_ID,
               L_TO_SUBINVENTORY,
               V_LOT.LOT_NUMBER,
               L_TRANSACTION_QUANTITY,
               SYSDATE,
               L_USER_ID,
               V1.LINE_NUM);
          
            IF L_REMAINING_QUANTITY = 0 THEN
              EXIT;
            END IF;
          END LOOP;
        END IF;
      
        PRINT_LOG(' start inv_txn_manager_pub.process_transactions  API ');
        --   COMMIT;
        V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                              P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                              P_COMMIT           => FND_API.G_TRUE,
                                                              P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                              X_RETURN_STATUS    => L_RETURN_STATUS,
                                                              X_MSG_COUNT        => L_MSG_CNT,
                                                              X_MSG_DATA         => L_MSG_DATA,
                                                              X_TRANS_COUNT      => L_TRANS_COUNT,
                                                              P_TABLE            => 1,
                                                              P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
        PRINT_LOG(' end inv_txn_manager_pub.process_transactions  API ');
        PRINT_LOG(' return status :- ' || NVL(L_RETURN_STATUS, 'E'));
        PRINT_LOG(' l_msg_cnt :- ' || NVL(L_MSG_CNT, 0));
      
        IF (NVL(L_RETURN_STATUS, 'E') <> 'S') THEN
          L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
        
          FOR I IN 1 .. L_MSG_CNT LOOP
            FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                            P_ENCODED       => 'F',
                            P_DATA          => L_MSG_DATA,
                            P_MSG_INDEX_OUT => X_MSG_INDEX);
            X_MSG := X_MSG || '.' || L_MSG_DATA;
          END LOOP;
        
          PRINT_LOG('Error in Subinventory Transfer:' || X_MSG);
          P_RET_STATUS := 'E';
          P_RET_MSG    := X_MSG;
        
          UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
             SET SUBINVENTORY_TRANSFER = 'E',
                 ERROR_MESSAGE         = SUBSTR(ERROR_MESSAGE ||
                                                ' SUBMIT:l_transaction_interface_id ' ||
                                                L_TRANSACTION_INTERFACE_ID ||
                                                P_RET_MSG,
                                                1,
                                                2000)
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND LRN_NO = P_LRN_NUMBER
             AND LINE_NUM = V1.LINE_NUM;
        ELSIF NVL(L_RETURN_STATUS, 'E') = 'S' THEN
          P_RET_STATUS := 'S';
          P_RET_MSG    := NULL;
          PRINT_LOG('Subinventory Transfer Successful');
        
          UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
             SET SUBINVENTORY_TRANSFER = 'Y'
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND LRN_NO = P_LRN_NUMBER
             AND LINE_NUM = V1.LINE_NUM;
        END IF;
      ELSE
        ----------------------------------------------------ADD BY GAUTAM ON 8-FEB-2021
        UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T T
           SET T.ERROR_MESSAGE = 'STOCK QTY IS LESS THEN LRN QTY.'
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND LRN_NO = P_LRN_NUMBER
           AND LINE_NUM = V1.LINE_NUM;
      END IF;
      ----------------------------------------------------ADD BY GAUTAM ON 8-FEB-2021
    END LOOP;
  
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'EXCEPTION IN SUBINVENTORY_TRANSFER:' || SQLERRM;
      PRINT_LOG('EXCEPTION IN SUBINVENTORY_TRANSFER:' || SQLERRM);
  END;

  /*--PROCEDURE REJECT_SUBINVENTORY_TRANSFER  ADDED BY YASHWANT ON 05-JUN-2019 AS PER CHANAGE REQUIRED BY BHUPESH
  */
  PROCEDURE REJECT_SUBINVENTORY_TRANSFER(P_ORGANIZATION_ID IN NUMBER,
                                         P_LRN_NUMBER      IN VARCHAR2,
                                         X_RETURN_STATUS   OUT VARCHAR2,
                                         X_MESSAGE         OUT VARCHAR2) IS
    L_USER_ID                  NUMBER := FND_PROFILE.VALUE('USER_ID');
    L_LOGIN_ID                 NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
    L_TRANSACTION_INTERFACE_ID NUMBER;
    V_RET_VAL                  NUMBER;
    L_RETURN_STATUS            VARCHAR2(100);
    L_MSG_CNT                  NUMBER;
    L_MSG_DATA                 VARCHAR2(4000);
    L_TRANS_COUNT              NUMBER;
    X_MSG_INDEX                NUMBER;
    X_MSG                      VARCHAR2(4000);
    L_TO_SUBINVENTORY          VARCHAR2(50);
    L_COUNT                    NUMBER;
    L_TRANSACTION_TYPE_ID      NUMBER;
    L_TRANSACTION_QUANTITY     NUMBER;
    L_REMAINING_QUANTITY       NUMBER;
    L_AVIL_ONHAND              NUMBER;
    L_VAL_FALG                 VARCHAR2(1);
    L_OU                       NUMBER;
    L_INTERFACE_ERROR          VARCHAR2(4000);
    CURSOR C1 IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD, XXMSSL.XXMSSL_LRN_HEADER_T XLH
       WHERE XLD.ORGANIZATION_ID = XLH.ORGANIZATION_ID
         AND XLD.LRN_NO = XLH.LRN_NO
         AND XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
         AND NVL(XLD.reject_process_flag, 'N') in ('N', 'E'); --v1.6 
  
    --added for v1.6 
    CURSOR C_LOT(P_INVENTORY_ITEM_ID NUMBER,
                 P_SUBINVENTORY_CODE IN VARCHAR2) IS
      SELECT *
        FROM (SELECT MLN.LOT_NUMBER,
                     MLN.CREATION_DATE,
                     XXMSSL_LRN_PKG.GET_OHQTY(MOQ.INVENTORY_ITEM_ID,
                                              MOQ.ORGANIZATION_ID,
                                              MOQ.SUBINVENTORY_CODE,
                                              MLN.LOT_NUMBER,
                                              'ATT') TRANSACTION_QUANTITY
                FROM MTL_ONHAND_QUANTITIES MOQ, MTL_LOT_NUMBERS MLN
               WHERE MOQ.ORGANIZATION_ID = MLN.ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
                 AND MLN.LOT_NUMBER = MOQ.LOT_NUMBER
                 AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
                 AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
               GROUP BY MLN.LOT_NUMBER,
                        MOQ.INVENTORY_ITEM_ID,
                        MOQ.ORGANIZATION_ID,
                        SUBINVENTORY_CODE,
                        MLN.CREATION_DATE)
       WHERE TRANSACTION_QUANTITY > 0
       ORDER BY CREATION_DATE;
  
    --AND XLH.LRN_STATUS = 'APPROVE'
    -- AND NVL (XLD.SUBINVENTORY_TRANSFER, 'N') = 'N';
    /*  
    ---v 1.8
    CURSOR C_LOT (
         P_INVENTORY_ITEM_ID        NUMBER,
         P_SUBINVENTORY_CODE   IN   VARCHAR2,
         P_LINE_NUM                 NUMBER
      )
      IS
         SELECT   XXLOT.LOT_NUMBER, XXLOT.CREATION_DATE,
                  SUM (XXLOT.LOT_QUANTITY) TRANSACTION_QUANTITY
             FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT
            WHERE 1 = 1
              AND XXLOT.LRN_NO = P_LRN_NUMBER
              AND XXLOT.LINE_NUMBER = P_LINE_NUM
              AND XXLOT.ORGANIZATION_ID = P_ORGANIZATION_ID
              AND XXLOT.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
              AND XXLOT.SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
         GROUP BY XXLOT.LOT_NUMBER, XXLOT.CREATION_DATE;*/
    --COMMENTED BY YASHWANT ON 15-OCT-2019-----------
    /*SELECT   MOQ.LOT_NUMBER, MOQ.DATE_RECEIVED,
             SUM (MOQ.TRANSACTION_QUANTITY) TRANSACTION_QUANTITY
        FROM MTL_ONHAND_QUANTITIES MOQ,
             XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT
       WHERE MOQ.LOT_NUMBER = XXLOT.LOT_NUMBER
         AND MOQ.ORGANIZATION_ID = XXLOT.ORGANIZATION_ID
         AND MOQ.INVENTORY_ITEM_ID = XXLOT.INVENTORY_ITEM_ID
         AND MOQ.SUBINVENTORY_CODE = XXLOT.SUBINVENTORY_CODE
         AND XXLOT.LRN_NO = P_LRN_NUMBER
         AND XXLOT.LINE_NUMBER = P_LINE_NUM
         AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
         AND MOQ.SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
    GROUP BY MOQ.LOT_NUMBER, MOQ.DATE_RECEIVED
    ORDER BY MOQ.DATE_RECEIVED;*/
  BEGIN
    G_LRN_NO     := P_LRN_NUMBER;
    G_ACTION     := ' REJECT_SUBINVENTORY_TRANSFER';
    G_REQUEST_ID := FND_GLOBAL.CONC_REQUEST_ID;
    PRINT_LOG('<----------- Reject Starting Subinventory Transfer Process ------------>');
    PRINT_LOG('LRN NO:- ' || P_LRN_NUMBER);
  
    /**************** GET TRANSACTION TYPE ***************************/
    BEGIN
      SELECT TRANSACTION_TYPE_ID
        INTO L_TRANSACTION_TYPE_ID
        FROM MTL_TRANSACTION_TYPES
       WHERE TRANSACTION_TYPE_NAME = 'LRN Transfers'
         AND TRANSACTION_SOURCE_TYPE_ID = 13;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRANSACTION_TYPE_ID := NULL;
    END;
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      PRINT_LOG('Transaction Type ''LRN Transfers'' is not Defined');
      X_RETURN_STATUS := 'E'; --ADDED BY YASHWANT
      X_MESSAGE       := 'Transaction Type ''LRN Transfers'' is not Defined';
      RETURN;
    END IF;
  
    /**************************** CHECK PERIOD IS OPEN ****************/
    SELECT COUNT(1)
      INTO L_COUNT
      FROM ORG_ACCT_PERIODS_V
     WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
       AND TRUNC(SYSDATE) BETWEEN START_DATE AND END_DATE
       AND UPPER(STATUS) = 'OPEN';
  
    IF L_COUNT = 0 THEN
      PRINT_LOG('Period is Not Open');
      X_RETURN_STATUS := 'E'; --ADDED BY YASHWANT
      X_MESSAGE       := 'Period is Not Open';
    
      P_PRAGMA_RECORDS('HEADER',
                       'SUBMIT',
                       'LRN',
                       P_LRN_NUMBER,
                       P_ORGANIZATION_ID,
                       NULL,
                       NULL,
                       X_MESSAGE,
                       G_REQUEST_ID);
      RETURN;
    END IF;
  
    BEGIN
      SELECT OPERATING_UNIT
        INTO L_OU
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_OU := NULL;
    END;
  
    MO_GLOBAL.SET_POLICY_CONTEXT('S', L_OU);
    INV_GLOBALS.SET_ORG_ID(P_ORGANIZATION_ID);
    MO_GLOBAL.INIT('INV');
  
    /********************* TO SUBINVENTORY *******************/
    BEGIN
      SELECT MSI.SECONDARY_INVENTORY_NAME
        INTO L_TO_SUBINVENTORY
        FROM FND_LOOKUP_VALUES            FLV,
             ORG_ORGANIZATION_DEFINITIONS OOD,
             MTL_SECONDARY_INVENTORIES    MSI
       WHERE LOOKUP_TYPE = 'XXMSSL_LRN_MRB_SUBINVENTORY'
         AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
         AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
         AND FLV.ENABLED_FLAG = 'Y'
         AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE)
         AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
         AND ROWNUM = 1;
    
      PRINT_LOG('l_to_subinventory:- ' || L_TO_SUBINVENTORY);
    EXCEPTION
      WHEN OTHERS THEN
        L_TO_SUBINVENTORY := NULL;
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Error : No Subinventory Defined in lookup ''XXMSSL_LRN_MRB_SUBINVENTORY'' For Subinventory Transfer');
        X_RETURN_STATUS := 'E'; --ADDED BY YASHWANT
        X_MESSAGE       := 'Error : No Subinventory Defined in lookup ''XXMSSL_LRN_MRB_SUBINVENTORY'' For Subinventory Transfer';
      
        P_PRAGMA_RECORDS('HEADER',
                         'SUBMIT',
                         'LRN',
                         P_LRN_NUMBER,
                         P_ORGANIZATION_ID,
                         NULL,
                         NULL,
                         X_MESSAGE,
                         G_REQUEST_ID);
        RETURN;
    END;
  
    ----------VALIDATION FOR CHECK LOT QTY-----
    L_VAL_FALG := 'Y';
    PRINT_LOG('start validate onhand quantity');
  
    /*---v1.6 comment by yashwant on 12-feb-2025 for onselete table XXMSSL.XXMSSL_LRN_SUBINV_LOT
    
    FOR I IN (SELECT   XXLOT.INVENTORY_ITEM_ID, MSI.SEGMENT1 ITEM_NAME,
                       XXLOT.ORGANIZATION_ID, XXLOT.SUBINVENTORY_CODE,
                       XXLOT.LOT_NUMBER,
                       SUM (XXLOT.LOT_QUANTITY) LOT_QUANTITY
                  FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT,
                       MTL_SYSTEM_ITEMS_B MSI
                 WHERE XXLOT.LRN_NO = P_LRN_NUMBER
                   AND XXLOT.ORGANIZATION_ID = P_ORGANIZATION_ID
                   AND XXLOT.INVENTORY_ITEM_ID = MSI.INVENTORY_ITEM_ID
                   AND XXLOT.ORGANIZATION_ID = MSI.ORGANIZATION_ID
                   AND XXLOT.SUBINVENTORY_CODE = L_TO_SUBINVENTORY
              GROUP BY XXLOT.INVENTORY_ITEM_ID,
                       XXLOT.ORGANIZATION_ID,
                       XXLOT.LOT_NUMBER,
                       XXLOT.SUBINVENTORY_CODE,
                       MSI.SEGMENT1)
    LOOP
       L_COUNT := 0;
       PRINT_LOG (   'organization_id:- '
                  || I.ORGANIZATION_ID
                  || ' inventory_item_id:-  '
                  || I.INVENTORY_ITEM_ID
                  || ' lrn_quantity '
                  || I.LOT_QUANTITY
                  || ' subinventory_code '
                  || I.SUBINVENTORY_CODE
                 );
    
       --CHECK ITEM IS LOT CONTROL OR NOT
       SELECT COUNT (*)
         INTO L_COUNT
         FROM MTL_SYSTEM_ITEMS_B
        WHERE ORGANIZATION_ID = I.ORGANIZATION_ID
          AND INVENTORY_ITEM_ID = I.INVENTORY_ITEM_ID
          AND LOT_CONTROL_CODE = 2;
    
       PRINT_LOG ('l_count:- ' || L_COUNT);
    
       --GET ITEM ONHAND 
       IF L_COUNT > 0
       THEN
          L_AVIL_ONHAND :=
             GET_OHQTY (I.INVENTORY_ITEM_ID,
                        I.ORGANIZATION_ID,
                        L_TO_SUBINVENTORY,
                        I.LOT_NUMBER,
                        'ATT'                    --AVAILABLE TO TRANSACT QTY
                       );
       ELSE
          SELECT XXMSSL_WIP_MOVE_ORDER_PKG.GET_ONHAND_QTY
                                                       (I.ORGANIZATION_ID,
                                                        I.INVENTORY_ITEM_ID,
                                                        L_TO_SUBINVENTORY
                                                       )
            INTO L_AVIL_ONHAND
            FROM DUAL;
       END IF;*/
  
    FOR V1 IN C1 LOOP
    
      L_RETURN_STATUS := NULL;
      L_MSG_CNT       := NULL;
      L_MSG_DATA      := NULL;
      L_TRANS_COUNT   := NULL;
      L_VAL_FALG      := 'N';
      PRINT_LOG('inventory_item_id :- ' || V1.INVENTORY_ITEM_ID);
      PRINT_LOG('subinventory_code :- ' || V1.SUBINVENTORY_CODE);
      PRINT_LOG('lrn_quantity :- ' || V1.LRN_QUANTITY);
    
      SELECT XXMSSL_WIP_MOVE_ORDER_PKG.GET_ONHAND_QTY(v1.ORGANIZATION_ID,
                                                      v1.INVENTORY_ITEM_ID,
                                                      L_TO_SUBINVENTORY)
        INTO L_AVIL_ONHAND
        FROM DUAL;
    
      PRINT_LOG('l_avil_onhand:- ' || L_AVIL_ONHAND);
    
      /*CHECK ON HAND IS AVAILABLE FOR TRANSACT QTY.*/
      IF L_AVIL_ONHAND < V1.LRN_QUANTITY THEN
        L_VAL_FALG := 'E';
        X_MESSAGE  := X_MESSAGE || ' Insufficient ohhand qty. for item ' ||
                      v1.ITEM_code;
        PRINT_LOG('x_message:- ' || X_MESSAGE);
        P_PRAGMA_RECORDS('LINE',
                         'SUBMIT',
                         'LRN',
                         P_LRN_NUMBER,
                         P_ORGANIZATION_ID,
                         V1.LINE_NUM,
                         v1.INVENTORY_ITEM_ID,
                         X_MESSAGE,
                         G_REQUEST_ID);
      END IF;
    
      PRINT_LOG('end validate onhand quantity');
    
      --------
    
      IF L_VAL_FALG = 'N' THEN
      
        SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
          INTO L_TRANSACTION_INTERFACE_ID
          FROM DUAL;
      
        PRINT_LOG(' start insert into mtl_transactions_interface');
      
        INSERT INTO MTL_TRANSACTIONS_INTERFACE
          (CREATED_BY,
           CREATION_DATE,
           INVENTORY_ITEM_ID,
           LAST_UPDATED_BY,
           LAST_UPDATE_DATE,
           LAST_UPDATE_LOGIN,
           LOCK_FLAG,
           ORGANIZATION_ID,
           PROCESS_FLAG,
           SOURCE_CODE,
           SOURCE_HEADER_ID,
           SOURCE_LINE_ID,
           SUBINVENTORY_CODE,
           TRANSACTION_DATE,
           TRANSACTION_HEADER_ID,
           TRANSACTION_INTERFACE_ID,
           TRANSACTION_MODE,
           TRANSACTION_QUANTITY,
           TRANSACTION_TYPE_ID,
           TRANSACTION_UOM,
           TRANSFER_SUBINVENTORY,
           TRANSACTION_REFERENCE)
        VALUES
          (L_USER_ID,
           SYSDATE,
           V1.INVENTORY_ITEM_ID,
           L_USER_ID,
           SYSDATE,
           L_LOGIN_ID,
           2,
           P_ORGANIZATION_ID,
           1,
           'LRN Subinventory Transfer',
           1,
           2,
           L_TO_SUBINVENTORY,
           SYSDATE,
           L_TRANSACTION_INTERFACE_ID,
           L_TRANSACTION_INTERFACE_ID,
           3,
           V1.LRN_QUANTITY,
           L_TRANSACTION_TYPE_ID,
           V1.UOM,
           V1.SUBINVENTORY_CODE,
           P_LRN_NUMBER);
      
        INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
          (CREATED_BY,
           CREATION_DATE,
           INVENTORY_ITEM_ID,
           LAST_UPDATED_BY,
           LAST_UPDATE_DATE,
           LAST_UPDATE_LOGIN,
           LOCK_FLAG,
           ORGANIZATION_ID,
           PROCESS_FLAG,
           SOURCE_CODE,
           SOURCE_HEADER_ID,
           SOURCE_LINE_ID,
           SUBINVENTORY_CODE,
           TRANSACTION_DATE,
           TRANSACTION_HEADER_ID,
           TRANSACTION_INTERFACE_ID,
           TRANSACTION_MODE,
           TRANSACTION_QUANTITY,
           TRANSACTION_TYPE_ID,
           TRANSACTION_UOM,
           TRANSFER_SUBINVENTORY,
           TRANSACTION_REFERENCE)
        VALUES
          (L_USER_ID,
           SYSDATE,
           V1.INVENTORY_ITEM_ID,
           L_USER_ID,
           SYSDATE,
           L_LOGIN_ID,
           2,
           P_ORGANIZATION_ID,
           1,
           'LRN Subinventory Transfer',
           1,
           2,
           L_TO_SUBINVENTORY,
           SYSDATE,
           L_TRANSACTION_INTERFACE_ID,
           L_TRANSACTION_INTERFACE_ID,
           3,
           V1.LRN_QUANTITY,
           L_TRANSACTION_TYPE_ID,
           V1.UOM,
           V1.SUBINVENTORY_CODE,
           P_LRN_NUMBER);
      
        PRINT_LOG(' end  insert into mtl_transactions_interface');
      
        /***************** CHECK ITEM IS LOT CONTROLLED ***************/
        SELECT COUNT(1)
          INTO L_COUNT
          FROM MTL_SYSTEM_ITEMS_B
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND INVENTORY_ITEM_ID = V1.INVENTORY_ITEM_ID
           AND LOT_CONTROL_CODE = 2;
      
        PRINT_LOG(' check item is lot control l_count = ' || L_COUNT);
      
        IF L_COUNT > 0 THEN
          L_REMAINING_QUANTITY := V1.LRN_QUANTITY;
        
          --        comment for v1 1.6     
          --FOR V_LOT IN C_LOT (V1.INVENTORY_ITEM_ID,
          --                                L_TO_SUBINVENTORY,
          --                                V1.LINE_NUM
          --                               )
        
          FOR V_LOT IN C_LOT(V1.INVENTORY_ITEM_ID, L_TO_SUBINVENTORY) LOOP
            PRINT_LOG(' insert into lot loop l_remaining_quantity=  ' ||
                      L_REMAINING_QUANTITY);
            L_TRANSACTION_QUANTITY := NULL;
            PRINT_LOG(' lot_quantity =  ' || V_LOT.TRANSACTION_QUANTITY);
            PRINT_LOG(' Lot no.  =  ' || V_LOT.LOT_NUMBER);
          
            IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
              L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
              L_REMAINING_QUANTITY   := 0;
            ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
              L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
              L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                        V_LOT.TRANSACTION_QUANTITY;
            END IF;
          
            PRINT_LOG(' l_remaining_quantity =  ' || L_REMAINING_QUANTITY);
            PRINT_LOG(' l_transaction_quantity  ' ||
                      L_TRANSACTION_QUANTITY);
            PRINT_LOG(' Insert into mtl_transaction_lots_interface  ');
          
            INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
              (TRANSACTION_INTERFACE_ID,
               LOT_NUMBER,
               TRANSACTION_QUANTITY,
               LAST_UPDATE_DATE,
               LAST_UPDATED_BY,
               CREATION_DATE,
               CREATED_BY)
            VALUES
              (L_TRANSACTION_INTERFACE_ID,
               V_LOT.LOT_NUMBER,
               L_TRANSACTION_QUANTITY,
               SYSDATE,
               L_USER_ID,
               SYSDATE,
               L_USER_ID);
          
            IF L_REMAINING_QUANTITY = 0 THEN
              EXIT;
            END IF;
          END LOOP;
        END IF;
      
        PRINT_LOG(' start inv_txn_manager_pub.process_transactions  API ');
        --   COMMIT;
        V_RET_VAL       := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                                    P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                                    P_COMMIT           => FND_API.G_TRUE,
                                                                    P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                                    X_RETURN_STATUS    => L_RETURN_STATUS,
                                                                    X_MSG_COUNT        => L_MSG_CNT,
                                                                    X_MSG_DATA         => L_MSG_DATA,
                                                                    X_TRANS_COUNT      => L_TRANS_COUNT,
                                                                    P_TABLE            => 1,
                                                                    P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
        X_RETURN_STATUS := L_RETURN_STATUS; --ADDED BY YASHWANT
        PRINT_LOG(' end inv_txn_manager_pub.process_transactions  API ');
        PRINT_LOG(' return status :- ' || NVL(X_RETURN_STATUS, 'E'));
        PRINT_LOG(' l_msg_cnt :- ' || NVL(L_MSG_CNT, 0));
      
        IF (NVL(L_RETURN_STATUS, 'E') <> 'S') THEN
          L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
        
          FOR I IN 1 .. L_MSG_CNT LOOP
            FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                            P_ENCODED       => 'F',
                            P_DATA          => L_MSG_DATA,
                            P_MSG_INDEX_OUT => X_MSG_INDEX);
            X_MSG := X_MSG || '.' || L_MSG_DATA;
          END LOOP;
        
          PRINT_LOG('Error in Reject Subinventory Transfer:' || X_MSG);
        
          BEGIN
            SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
              INTO L_INTERFACE_ERROR
              FROM MTL_TRANSACTIONS_INTERFACE
             WHERE TRANSACTION_INTERFACE_ID = L_TRANSACTION_INTERFACE_ID
               AND SOURCE_CODE = 'LRN Subinventory Transfer';
          EXCEPTION
            WHEN OTHERS THEN
              L_INTERFACE_ERROR := NULL;
          END;
        
          PRINT_LOG('Error in Reject Subinventory Transfer:' || X_MSG);
        
          UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
             SET reject_process_flag = 'E',
                 ERROR_MESSAGE       = SUBSTR(ERROR_MESSAGE ||
                                              ' REJECT:l_transaction_interface_id ' ||
                                              L_TRANSACTION_INTERFACE_ID ||
                                              L_INTERFACE_ERROR,
                                              1,
                                              2000)
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND LRN_NO = P_LRN_NUMBER
             AND LINE_NUM = V1.LINE_NUM;
        
          X_MESSAGE := 'Error in Reject Subinventory Transfer:' || X_MSG;
        ELSIF NVL(L_RETURN_STATUS, 'E') = 'S' THEN
          PRINT_LOG('Reject Subinventory Transfer Successful');
        
          UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
             SET reject_process_flag = 'R'
             , ERROR_MESSAGE = NULL
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND LRN_NO = P_LRN_NUMBER
             AND LINE_NUM = V1.LINE_NUM;
        END IF;
      
      END IF;
    END LOOP;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      PRINT_LOG('Exception in reject subinventory_transfer:' || SQLERRM);
      X_RETURN_STATUS := 'E'; --ADDED BY YASHWANT
      X_MESSAGE       := 'Exception in reject subinventory_transfer:' ||
                         SQLERRM;
      P_PRAGMA_RECORDS('HEADER',
                       'SUBMIT',
                       'LRN',
                       P_LRN_NUMBER,
                       P_ORGANIZATION_ID,
                       NULL,
                       NULL,
                       X_MESSAGE,
                       G_REQUEST_ID);
  END REJECT_SUBINVENTORY_TRANSFER;

  PROCEDURE MOVE_ORDER_TRANSFER(P_ORGANIZATION_ID IN NUMBER,
                                P_LRN_NUMBER      IN VARCHAR2) IS
    -- COMMON DECLARATIONS
    L_API_VERSION         NUMBER := 1.0;
    L_INIT_MSG_LIST       VARCHAR2(2) := FND_API.G_TRUE;
    L_RETURN_VALUES       VARCHAR2(2) := FND_API.G_TRUE;
    L_COMMIT              VARCHAR2(2) := FND_API.G_FALSE;
    X_RETURN_STATUS       VARCHAR2(2);
    X_MSG_COUNT           NUMBER := 0;
    X_MSG_DATA            VARCHAR2(255);
    L_TRANSACTION_TYPE_ID NUMBER := NULL;
    L_HEADER_ID           NUMBER := NULL;
    L_USER_ID             NUMBER := FND_GLOBAL.USER_ID;
    L_RESP_ID             NUMBER := FND_GLOBAL.RESP_ID;
    L_APPLICATION_ID      NUMBER := FND_GLOBAL.RESP_APPL_ID;
    L_ROW_CNT             NUMBER := 0;
    L_TROHDR_REC          INV_MOVE_ORDER_PUB.TROHDR_REC_TYPE;
    L_TROHDR_VAL_REC      INV_MOVE_ORDER_PUB.TROHDR_VAL_REC_TYPE;
    X_TROHDR_REC          INV_MOVE_ORDER_PUB.TROHDR_REC_TYPE;
    X_TROHDR_VAL_REC      INV_MOVE_ORDER_PUB.TROHDR_VAL_REC_TYPE;
    L_VALIDATION_FLAG     VARCHAR2(2) := INV_MOVE_ORDER_PUB.G_VALIDATION_YES;
    L_TROLIN_TBL          INV_MOVE_ORDER_PUB.TROLIN_TBL_TYPE;
    L_TROLIN_VAL_TBL      INV_MOVE_ORDER_PUB.TROLIN_VAL_TBL_TYPE;
    X_TROLIN_TBL          INV_MOVE_ORDER_PUB.TROLIN_TBL_TYPE;
    X_TROLIN_VAL_TBL      INV_MOVE_ORDER_PUB.TROLIN_VAL_TBL_TYPE;
    L_TO_SUBINVENTORY     VARCHAR2(10);
  
    CURSOR C_MO_LINES IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD, XXMSSL.XXMSSL_LRN_HEADER_T XLH
       WHERE XLD.ORGANIZATION_ID = XLH.ORGANIZATION_ID
         AND XLD.LRN_NO = XLH.LRN_NO
         AND XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
         AND XLH.LRN_STATUS IN( 'APPROVE','COMPLETE')
         AND NVL(XLD.MOVE_ORDER_TRANSFER, 'N') = 'N'
         AND SUBINVENTORY_TRANSFER = 'Y'
         AND ((JOB_ITEM_FLAG = 'J') OR
             (JOB_ITEM_FLAG = 'I' AND
             SUBINVENTORY_CODE = L_TO_SUBINVENTORY));
  BEGIN
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      '<------------- Starting Move Order Transfer Process --------------->');
  
    /**************** GET TRANSACTION TYPE ***************************/
    BEGIN
      SELECT TRANSACTION_TYPE_ID
        INTO L_TRANSACTION_TYPE_ID
        FROM MTL_TRANSACTION_TYPES
       WHERE TRANSACTION_TYPE_NAME = 'LRN Move Orders'
         AND TRANSACTION_SOURCE_TYPE_ID = 4;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRANSACTION_TYPE_ID := NULL;
    END;
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Transaction Type ''LRN Move Orders'' is not Defined');
      RETURN;
    END IF;
  
    /********************* WIP SUBINVENTORY VALIDATION *******************/
    BEGIN
      SELECT MSI.SECONDARY_INVENTORY_NAME
        INTO L_TO_SUBINVENTORY
        FROM FND_LOOKUP_VALUES            FLV,
             ORG_ORGANIZATION_DEFINITIONS OOD,
             MTL_SECONDARY_INVENTORIES    MSI
       WHERE LOOKUP_TYPE = 'XXMSSL_LRN_SUBINVENTORY_TRF'
         AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
         AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
         AND FLV.ENABLED_FLAG = 'Y'
         AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE)
         AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
         AND ROWNUM = 1;
    EXCEPTION
      WHEN OTHERS THEN
        L_TO_SUBINVENTORY := NULL;
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Error : No Subinventory Defined in lookup ''XXMSSL_LRN_SUBINVENTORY_TRF'' For Subinventory Transfer');
        RETURN;
    END;
  
    FND_GLOBAL.APPS_INITIALIZE(L_USER_ID, L_RESP_ID, L_APPLICATION_ID);
    L_TROHDR_REC.DATE_REQUIRED       := SYSDATE;
    L_TROHDR_REC.ORGANIZATION_ID     := P_ORGANIZATION_ID;
    L_TROHDR_REC.STATUS_DATE         := SYSDATE;
    L_TROHDR_REC.HEADER_STATUS       := INV_GLOBALS.G_TO_STATUS_PREAPPROVED;
    L_TROHDR_REC.TRANSACTION_TYPE_ID := L_TRANSACTION_TYPE_ID;
    L_TROHDR_REC.MOVE_ORDER_TYPE     := INV_GLOBALS.G_MOVE_ORDER_REQUISITION;
    L_TROHDR_REC.DB_FLAG             := FND_API.G_TRUE;
    L_TROHDR_REC.OPERATION           := INV_GLOBALS.G_OPR_CREATE;
    --L_TROHDR_REC.ATTRIBUTE15         := P_LRN_NUMBER;
    L_TROHDR_REC.DESCRIPTION       := 'LRN No# ' || P_LRN_NUMBER;
    L_TROHDR_REC.CREATED_BY        := L_USER_ID;
    L_TROHDR_REC.CREATION_DATE     := SYSDATE;
    L_TROHDR_REC.LAST_UPDATED_BY   := L_USER_ID;
    L_TROHDR_REC.LAST_UPDATE_DATE  := SYSDATE;
    L_TROHDR_REC.LAST_UPDATE_LOGIN := FND_GLOBAL.LOGIN_ID;
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      'Calling INV_MOVE_ORDER_PUB.Create_Move_Order_Header API');
    INV_MOVE_ORDER_PUB.CREATE_MOVE_ORDER_HEADER(P_API_VERSION_NUMBER => L_API_VERSION,
                                                P_INIT_MSG_LIST      => L_INIT_MSG_LIST,
                                                P_RETURN_VALUES      => L_RETURN_VALUES,
                                                P_COMMIT             => L_COMMIT,
                                                X_RETURN_STATUS      => X_RETURN_STATUS,
                                                X_MSG_COUNT          => X_MSG_COUNT,
                                                X_MSG_DATA           => X_MSG_DATA,
                                                P_TROHDR_REC         => L_TROHDR_REC,
                                                P_TROHDR_VAL_REC     => L_TROHDR_VAL_REC,
                                                X_TROHDR_REC         => X_TROHDR_REC,
                                                X_TROHDR_VAL_REC     => X_TROHDR_VAL_REC,
                                                P_VALIDATION_FLAG    => L_VALIDATION_FLAG);
    FND_FILE.PUT_LINE(FND_FILE.LOG, 'Return Status: ' || X_RETURN_STATUS);
  
    IF (X_RETURN_STATUS <> FND_API.G_RET_STS_SUCCESS) THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Error Message :' || X_MSG_DATA);
    ELSIF (X_RETURN_STATUS = FND_API.G_RET_STS_SUCCESS) THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Move Order Created Successfully');
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Move Order Header ID : ' || X_TROHDR_REC.HEADER_ID);
      L_HEADER_ID := X_TROHDR_REC.HEADER_ID;
    END IF;
  
    IF L_HEADER_ID IS NOT NULL THEN
      FOR ORDLINES IN C_MO_LINES LOOP
        X_MSG_DATA := NULL;
        X_RETURN_STATUS := NULL;
        L_ROW_CNT := L_ROW_CNT + 1;
        L_TROLIN_TBL(L_ROW_CNT).HEADER_ID := L_HEADER_ID;
        L_TROLIN_TBL(L_ROW_CNT).DATE_REQUIRED := SYSDATE;
        L_TROLIN_TBL(L_ROW_CNT).ORGANIZATION_ID := P_ORGANIZATION_ID;
        L_TROLIN_TBL(L_ROW_CNT).INVENTORY_ITEM_ID := ORDLINES.INVENTORY_ITEM_ID;
        -- L_TROLIN_TBL(L_ROW_CNT).FROM_SUBINVENTORY_CODE := ORDLINES.SUBINVENTORY_CODE;
        L_TROLIN_TBL(L_ROW_CNT).TO_SUBINVENTORY_CODE := ORDLINES.SUBINVENTORY_CODE;
        L_TROLIN_TBL(L_ROW_CNT).QUANTITY := ORDLINES.LRN_QUANTITY;
        L_TROLIN_TBL(L_ROW_CNT).STATUS_DATE := SYSDATE;
        L_TROLIN_TBL(L_ROW_CNT).UOM_CODE := ORDLINES.UOM;
        L_TROLIN_TBL(L_ROW_CNT).LINE_NUMBER := L_ROW_CNT;
        L_TROLIN_TBL(L_ROW_CNT).LINE_STATUS := INV_GLOBALS.G_TO_STATUS_PREAPPROVED;
        L_TROLIN_TBL(L_ROW_CNT).DB_FLAG := FND_API.G_TRUE;
        L_TROLIN_TBL(L_ROW_CNT).OPERATION := INV_GLOBALS.G_OPR_CREATE;
        L_TROLIN_TBL(L_ROW_CNT).CREATED_BY := L_USER_ID;
        L_TROLIN_TBL(L_ROW_CNT).CREATION_DATE := SYSDATE;
        L_TROLIN_TBL(L_ROW_CNT).LAST_UPDATED_BY := L_USER_ID;
        L_TROLIN_TBL(L_ROW_CNT).LAST_UPDATE_DATE := SYSDATE;
        L_TROLIN_TBL(L_ROW_CNT).LAST_UPDATE_LOGIN := FND_GLOBAL.LOGIN_ID;
        L_TROLIN_TBL(L_ROW_CNT).TRANSACTION_TYPE_ID := L_TRANSACTION_TYPE_ID;
        L_TROLIN_TBL(L_ROW_CNT).ATTRIBUTE1 := ORDLINES.JOB_NUMBER;
        --L_TROLIN_TBL(L_ROW_CNT).ATTRIBUTE12 := ORDLINES.LRN_NO;
        L_TROLIN_TBL(L_ROW_CNT).REFERENCE := ORDLINES.LRN_NO;
        L_TROLIN_TBL(L_ROW_CNT).ATTRIBUTE13 := ORDLINES.LINE_NUM;
        L_TROLIN_TBL(L_ROW_CNT).ATTRIBUTE15 := ORDLINES.ITEM_CODE;
      END LOOP;
    
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Calling INV_MOVE_ORDER_PUB.Create_Move_Order_Lines API');
      INV_MOVE_ORDER_PUB.CREATE_MOVE_ORDER_LINES(P_API_VERSION_NUMBER => L_API_VERSION,
                                                 P_INIT_MSG_LIST      => L_INIT_MSG_LIST,
                                                 P_RETURN_VALUES      => L_RETURN_VALUES,
                                                 P_COMMIT             => L_COMMIT,
                                                 X_RETURN_STATUS      => X_RETURN_STATUS,
                                                 X_MSG_COUNT          => X_MSG_COUNT,
                                                 X_MSG_DATA           => X_MSG_DATA,
                                                 P_TROLIN_TBL         => L_TROLIN_TBL,
                                                 P_TROLIN_VAL_TBL     => L_TROLIN_VAL_TBL,
                                                 X_TROLIN_TBL         => X_TROLIN_TBL,
                                                 X_TROLIN_VAL_TBL     => X_TROLIN_VAL_TBL,
                                                 P_VALIDATION_FLAG    => L_VALIDATION_FLAG);
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Return Status: ' || X_RETURN_STATUS);
    
      IF (X_RETURN_STATUS <> FND_API.G_RET_STS_SUCCESS) THEN
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Error in Move Order Transfer :' || X_MSG_DATA);
      
        UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
           SET MOVE_ORDER_TRANSFER = 'E'
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND LRN_NO = P_LRN_NUMBER;
      ELSIF (X_RETURN_STATUS = FND_API.G_RET_STS_SUCCESS) THEN
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Move Order Lines Created Successfully for ' ||
                          L_HEADER_ID);
      
        UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
           SET MOVE_ORDER_TRANSFER = 'Y'
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND LRN_NO = P_LRN_NUMBER;
      END IF;
    ELSIF L_HEADER_ID IS NULL THEN
      UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
         SET MOVE_ORDER_TRANSFER = 'E'
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND LRN_NO = P_LRN_NUMBER;
    END IF;
  
    /*CODE ADDED BY SUNEET KHARBANDA ON DATED 27-JUL-17 AGAINST CEMLI C062*/
    BEGIN
      UPDATE XXMSSL_LRN_HEADER_T
         SET MOVE_ORDER_NUMBER = X_TROHDR_REC.REQUEST_NUMBER
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND LRN_NO = P_LRN_NUMBER;
    END;
    /*CODE ENDED HERE*/
  
    --  COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Exception Occured :');
      FND_FILE.PUT_LINE(FND_FILE.LOG, SQLCODE || ':' || SQLERRM);
  END MOVE_ORDER_TRANSFER;

  /*--PROCEDURE LRN_SCARP_ISSUE  ADDED BY YASHWANT ON 10-JUN-2019 AS PER CHANAGE REQUIRED BY BHUPESH
  NEW TRANSACTION TYPE LRN SCRAP IS USED ISSUE ITEM FROM SCRAP SUB INVENTORY.
  */
  PROCEDURE LRN_SCARP_ISSUE(ERRBUF              OUT VARCHAR2,
                            RETCODE             OUT NUMBER,
                            P_ORGANIZATION_ID   IN NUMBER,
                            P_LRN_NUMBER        IN VARCHAR2,
                            P_FROM_SUBINVENTORY IN VARCHAR2,
                            P_ITEM_ID           IN NUMBER,
                            P_LINE_NUM          IN NUMBER) IS
    L_USER_ID                  NUMBER := FND_PROFILE.VALUE('USER_ID');
    L_LOGIN_ID                 NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
    L_TRANSACTION_INTERFACE_ID NUMBER;
    V_RET_VAL                  NUMBER;
    L_RETURN_STATUS            VARCHAR2(100);
    L_MSG_CNT                  NUMBER;
    L_MSG_DATA                 VARCHAR2(4000);
    L_TRANS_COUNT              NUMBER;
    X_MSG_INDEX                NUMBER;
    X_MSG                      VARCHAR2(4000);
    L_TO_SUBINVENTORY          VARCHAR2(50);
    L_COUNT                    NUMBER;
    L_TRANSACTION_TYPE_ID      NUMBER;
    L_TRANSACTION_QUANTITY     NUMBER;
    L_REMAINING_QUANTITY       NUMBER;
    L_OU                       NUMBER;
    L_SEGMENT2                 VARCHAR2(40);
    L_TRAN_TYPE                VARCHAR2(50);
    --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
    L_TYPE VARCHAR2(50);
  
    --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
    CURSOR C_SCRAP_QTY IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD
       WHERE XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
         AND XLD.INVENTORY_ITEM_ID = P_ITEM_ID
         AND XLD.COMPLETE_FLAG = 'YES'
         AND XLD.LINE_NUM = P_LINE_NUM
         AND NVL(XLD.SCRAP_SUBINVENTORY_TRF, 'N') = 'Y'
         AND NVL(SCRAPPED_QUANTITY, 0) > 0;
  
    CURSOR C_LOT(P_INVENTORY_ITEM_ID NUMBER,
                 P_SUBINVENTORY_CODE IN VARCHAR2) IS
       SELECT   *
             FROM (SELECT   MLN.LOT_NUMBER, MLN.CREATION_DATE,
                            XXMSSL_LRN_PKG.GET_OHQTY
                                 (MOQ.INVENTORY_ITEM_ID,
                                  MOQ.ORGANIZATION_ID,
                                  MOQ.SUBINVENTORY_CODE,
                                  MLN.LOT_NUMBER,
                                  'ATT'
                                 ) TRANSACTION_QUANTITY
                       FROM MTL_ONHAND_QUANTITIES MOQ, MTL_LOT_NUMBERS MLN
                      WHERE MOQ.ORGANIZATION_ID = MLN.ORGANIZATION_ID
                        AND MOQ.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
                        AND MLN.LOT_NUMBER = MOQ.LOT_NUMBER
                        AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
                        AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
                        AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
                   GROUP BY MLN.LOT_NUMBER,
                            MOQ.INVENTORY_ITEM_ID,
                            MOQ.ORGANIZATION_ID,
                            SUBINVENTORY_CODE,
                            MLN.CREATION_DATE)
            WHERE TRANSACTION_QUANTITY > 0
         ORDER BY CREATION_DATE;
      
    ---comment by yashwant for v1.6-----  
    /*  SELECT MOQ.LOT_NUMBER,
             MOQ.DATE_RECEIVED,
             SUM(MOQ.TRANSACTION_QUANTITY) TRANSACTION_QUANTITY
        FROM MTL_ONHAND_QUANTITIES MOQ, XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT
       WHERE MOQ.LOT_NUMBER = XXLOT.LOT_NUMBER
         AND MOQ.ORGANIZATION_ID = XXLOT.ORGANIZATION_ID
         AND MOQ.INVENTORY_ITEM_ID = XXLOT.INVENTORY_ITEM_ID
         AND XXLOT.LRN_NO = P_LRN_NUMBER
         AND XXLOT.LINE_NUMBER = P_LINE_NUM
         AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
         AND MOQ.SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
       GROUP BY MOQ.LOT_NUMBER, MOQ.DATE_RECEIVED
       ORDER BY MOQ.DATE_RECEIVED;*/
  BEGIN
    BEGIN
      SELECT OPERATING_UNIT
        INTO L_OU
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_OU := NULL;
    END;
  
    BEGIN
      SELECT TRANSACTION_TYPE
        INTO L_TRAN_TYPE
        FROM XXMSSL_LRN_HEADER_T
       WHERE LRN_NO = P_LRN_NUMBER
         AND ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRAN_TYPE := NULL;
    END; --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
  
    BEGIN
      SELECT DECODE(L_TRAN_TYPE, 'LRN', 'LRN Scrap', 'MRN', 'MRN Scrap')
        INTO L_TYPE
        FROM DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        L_TYPE := NULL;
    END; --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
  
    MO_GLOBAL.SET_POLICY_CONTEXT('S', L_OU);
    INV_GLOBALS.SET_ORG_ID(P_ORGANIZATION_ID);
    MO_GLOBAL.INIT('INV');
    PRINT_LOG('<----------- Starting Scrap issue Process ------------>');
  
    /**************** GET TRANSACTION TYPE ***************************/
    BEGIN
      SELECT TRANSACTION_TYPE_ID
        INTO L_TRANSACTION_TYPE_ID
        FROM MTL_TRANSACTION_TYPES
       WHERE TRANSACTION_TYPE_NAME =
             DECODE(L_TRAN_TYPE, 'LRN', 'LRN Scrap', 'MRN', 'MRN Scrap')
            --= 'LRN SCRAP'--ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
         AND TRANSACTION_SOURCE_TYPE_ID = 13;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRANSACTION_TYPE_ID := NULL;
    END;
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      PRINT_LOG('Transaction Type '' LRN Scrap/MRN Scrap '' is not Defined');
      RETURN;
    END IF;
  
    FOR V_SCRAP_QTY IN C_SCRAP_QTY LOOP
      L_RETURN_STATUS := NULL;
      L_MSG_CNT       := NULL;
      L_MSG_DATA      := NULL;
      L_TRANS_COUNT   := NULL;
      PRINT_LOG('inventory_item_id :- ' || V_SCRAP_QTY.INVENTORY_ITEM_ID);
      PRINT_LOG('line_num :- ' || V_SCRAP_QTY.LINE_NUM);
      PRINT_LOG('scrapped_quantity :- ' || V_SCRAP_QTY.SCRAPPED_QUANTITY);
      
      
      ----v1.6--delete interface stuck records
      DELETE 
              FROM   MTL_TRANSACTION_LOTS_INTERFACE 
              WHERE TRANSACTION_INTERFACE_ID in ( SELECT TRANSACTION_INTERFACE_ID
                                                   FROM   MTL_TRANSACTIONS_INTERFACE  
                                                  WHERE TRANSACTION_REFERENCE = V_SCRAP_QTY.lrn_no
                                                  AND organization_id = V_SCRAP_QTY.organization_id
                                                  AND inventory_item_id =  V_SCRAP_QTY.inventory_item_id
                                                  AND SUBINVENTORY_CODE = P_FROM_SUBINVENTORY);
                
               DELETE FROM   MTL_TRANSACTIONS_INTERFACE  
               WHERE TRANSACTION_REFERENCE = V_SCRAP_QTY.lrn_no
               AND organization_id         = V_SCRAP_QTY.organization_id
               AND inventory_item_id       =  V_SCRAP_QTY.inventory_item_id
               AND SUBINVENTORY_CODE       =  P_FROM_SUBINVENTORY;
      
    
      SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
        INTO L_TRANSACTION_INTERFACE_ID
        FROM DUAL;
    
      INSERT INTO MTL_TRANSACTIONS_INTERFACE
        (CREATED_BY,
         CREATION_DATE,
         INVENTORY_ITEM_ID,
         LAST_UPDATED_BY,
         LAST_UPDATE_DATE,
         LAST_UPDATE_LOGIN,
         LOCK_FLAG,
         ORGANIZATION_ID,
         PROCESS_FLAG,
         SOURCE_CODE,
         TRANSACTION_SOURCE_NAME,
         SOURCE_HEADER_ID,
         SOURCE_LINE_ID,
         SUBINVENTORY_CODE,
         TRANSACTION_DATE,
         TRANSACTION_HEADER_ID,
         TRANSACTION_INTERFACE_ID,
         TRANSACTION_MODE,
         TRANSACTION_QUANTITY,
         TRANSACTION_TYPE_ID,
         TRANSACTION_UOM,
         ATTRIBUTE13,
         ATTRIBUTE14,
         ATTRIBUTE15,
         TRANSACTION_REFERENCE)
      VALUES
        (L_USER_ID,
         SYSDATE,
         V_SCRAP_QTY.INVENTORY_ITEM_ID,
         L_USER_ID,
         SYSDATE,
         L_LOGIN_ID,
         2,
         P_ORGANIZATION_ID,
         1,
         L_TYPE,
         --'LRN SCRAP',--ADDED BY DALJEET ON 30-NOV-2020  FOR IDACS
         L_TYPE,
         --'LRN SCRAP',--ADDED BY DALJEET ON 30-NOV-2020  FOR IDACS
         1,
         2,
         P_FROM_SUBINVENTORY,
         SYSDATE,
         L_TRANSACTION_INTERFACE_ID,
         L_TRANSACTION_INTERFACE_ID,
         3,
         V_SCRAP_QTY.SCRAPPED_QUANTITY * (-1),
         L_TRANSACTION_TYPE_ID,
         V_SCRAP_QTY.UOM,
         'SCRAP',
         P_LRN_NUMBER,
         V_SCRAP_QTY.LINE_NUM,
         P_LRN_NUMBER);
    
      INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
        (CREATED_BY,
         CREATION_DATE,
         INVENTORY_ITEM_ID,
         LAST_UPDATED_BY,
         LAST_UPDATE_DATE,
         LAST_UPDATE_LOGIN,
         LOCK_FLAG,
         ORGANIZATION_ID,
         PROCESS_FLAG,
         SOURCE_CODE,
         TRANSACTION_SOURCE_NAME,
         SOURCE_HEADER_ID,
         SOURCE_LINE_ID,
         SUBINVENTORY_CODE,
         TRANSACTION_DATE,
         TRANSACTION_HEADER_ID,
         TRANSACTION_INTERFACE_ID,
         TRANSACTION_MODE,
         TRANSACTION_QUANTITY,
         TRANSACTION_TYPE_ID,
         TRANSACTION_UOM,
         ATTRIBUTE13,
         ATTRIBUTE14,
         ATTRIBUTE15,
         TRANSACTION_REFERENCE)
      VALUES
        (L_USER_ID,
         SYSDATE,
         V_SCRAP_QTY.INVENTORY_ITEM_ID,
         L_USER_ID,
         SYSDATE,
         L_LOGIN_ID,
         2,
         P_ORGANIZATION_ID,
         1,
         L_TYPE,
         -- 'LRN SCRAP',--ADDED BY DALJEET ON 30-NOV-2020  FOR IDACS
         --                      'LRN SCRAP', --COMMENT OUT BY DALJEET ON 30-NOV-2020  FOR IDACS
         L_TYPE,
         1, --ADDED BY DALJEET ON 30-NOV-2020  FOR IDACS
         2,
         P_FROM_SUBINVENTORY,
         SYSDATE,
         L_TRANSACTION_INTERFACE_ID,
         L_TRANSACTION_INTERFACE_ID,
         3,
         V_SCRAP_QTY.SCRAPPED_QUANTITY * (-1),
         L_TRANSACTION_TYPE_ID,
         V_SCRAP_QTY.UOM,
         'SCRAP',
         P_LRN_NUMBER,
         V_SCRAP_QTY.LINE_NUM,
         P_LRN_NUMBER);
    
      /***************** CHECK ITEM IS LOT CONTROLLED ***************/
      SELECT COUNT(*)
        INTO L_COUNT
        FROM MTL_SYSTEM_ITEMS_B
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND INVENTORY_ITEM_ID = V_SCRAP_QTY.INVENTORY_ITEM_ID
         AND LOT_CONTROL_CODE = 2;
    
      IF L_COUNT > 0 THEN
        L_REMAINING_QUANTITY := V_SCRAP_QTY.SCRAPPED_QUANTITY;
      
        FOR V_LOT IN C_LOT(V_SCRAP_QTY.INVENTORY_ITEM_ID,
                           P_FROM_SUBINVENTORY) LOOP
          L_TRANSACTION_QUANTITY := NULL;
          PRINT_LOG('start insert into mtl_transaction_lots_interface ');
        
          IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
            L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
            L_REMAINING_QUANTITY   := 0;
          ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
            L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
            L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                      V_LOT.TRANSACTION_QUANTITY;
          END IF;
        
          PRINT_LOG('lot_quantity  ' || V_LOT.TRANSACTION_QUANTITY);
          PRINT_LOG('v_lot.lot_number  ' || V_LOT.LOT_NUMBER);
          PRINT_LOG('l_transaction_quantity  ' || L_TRANSACTION_QUANTITY);
        
          INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
            (TRANSACTION_INTERFACE_ID,
             LOT_NUMBER,
             TRANSACTION_QUANTITY,
             LAST_UPDATE_DATE,
             LAST_UPDATED_BY,
             CREATION_DATE,
             CREATED_BY)
          VALUES
            (L_TRANSACTION_INTERFACE_ID,
             V_LOT.LOT_NUMBER,
             L_TRANSACTION_QUANTITY,
             SYSDATE,
             L_USER_ID,
             SYSDATE,
             L_USER_ID);
        
          IF L_REMAINING_QUANTITY = 0 THEN
            EXIT;
          END IF;
        END LOOP;
      END IF;
    
      PRINT_LOG('start inv_txn_manager_pub.process_transactions API ');
      ---  COMMIT;
      V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                            P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                            P_COMMIT           => FND_API.G_TRUE,
                                                            P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                            X_RETURN_STATUS    => L_RETURN_STATUS,
                                                            X_MSG_COUNT        => L_MSG_CNT,
                                                            X_MSG_DATA         => L_MSG_DATA,
                                                            X_TRANS_COUNT      => L_TRANS_COUNT,
                                                            P_TABLE            => 1,
                                                            P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
      PRINT_LOG('end inv_txn_manager_pub.process_transactions API ');
      PRINT_LOG('l_return_status :-  ' || L_RETURN_STATUS);
      PRINT_LOG('l_msg_cnt :-  ' || L_MSG_CNT);
    
      IF (L_RETURN_STATUS <> 'S') THEN
        L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
      
        FOR I IN 1 .. L_MSG_CNT LOOP
          FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                          P_ENCODED       => 'F',
                          P_DATA          => L_MSG_DATA,
                          P_MSG_INDEX_OUT => X_MSG_INDEX);
          X_MSG := X_MSG || '.' || L_MSG_DATA;
        END LOOP;
      
        PRINT_LOG('Error in Scrap issue Transfer:' || X_MSG);
        ERRBUF := X_MSG;
      ELSIF L_RETURN_STATUS = 'S' THEN
        PRINT_LOG('Scrap issue Transfer Successful');
      END IF;
    END LOOP;
  END LRN_SCARP_ISSUE;

  PROCEDURE QUALITY_SUBINVENTORY_TRF(ERRBUF            OUT VARCHAR2,
                                     RETCODE           OUT NUMBER,
                                     P_ORGANIZATION_ID IN NUMBER,
                                     P_LRN_NUMBER      IN VARCHAR2) IS
    L_USER_ID                  NUMBER := FND_PROFILE.VALUE('USER_ID');
    L_LOGIN_ID                 NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
    L_TRANSACTION_INTERFACE_ID NUMBER;
    V_RET_VAL                  NUMBER;
    L_RETURN_STATUS            VARCHAR2(100);
    L_MSG_CNT                  NUMBER;
    L_MSG_DATA                 VARCHAR2(4000);
    L_TRANS_COUNT              NUMBER;
    X_MSG_INDEX                NUMBER;
    X_MSG                      VARCHAR2(4000);
    L_FROM_SUBINVENTORY        VARCHAR2(50); -- := 'MR001'; VIKAS 
    L_TO_SUBINVENTORY          VARCHAR2(50);
    L_COUNT                    NUMBER;
    L_TRANSACTION_TYPE_ID      NUMBER;
    L_TRANSACTION_QUANTITY     NUMBER;
    L_REMAINING_QUANTITY       NUMBER;
    L_OU                       NUMBER;
    L_SEGMENT2                 VARCHAR2(40);
    L_TRAN_TYPE                VARCHAR2(50);
    --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
    L_TYPE             VARCHAR2(50);
    L_SUBINVENTORY_CNT NUMBER := 0;
    L_INTERFACE_ERROR  VARCHAR2(4000);
    --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
    CURSOR C_MAIN IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD
       WHERE XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER;
  
    CURSOR C_STORE_QTY(P_LINE_NUMBER NUMBER) IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD
       WHERE XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
         AND XLD.COMPLETE_FLAG = 'YES'
         AND XLD.LINE_NUM = P_LINE_NUMBER
         AND NVL(XLD.STORE_SUBINVENTORY_TRF, 'N') IN ( 'N','E') --V 1.6 
         AND NVL(QTY_RETURN_TO_STORES, 0) > 0;
  
    CURSOR C_SCRAP_QTY(P_LINE_NUMBER NUMBER) IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD
       WHERE XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
         AND XLD.COMPLETE_FLAG = 'YES'
         AND XLD.LINE_NUM = P_LINE_NUMBER
         AND NVL(XLD.SCRAP_SUBINVENTORY_TRF, 'N') IN ( 'N','E') --V 1.6 
         AND NVL(SCRAPPED_QUANTITY, 0) > 0;
  
    CURSOR C_REJECT_QTY(P_LINE_NUMBER NUMBER) IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD
       WHERE XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
         AND XLD.COMPLETE_FLAG = 'YES'
         AND XLD.LINE_NUM = P_LINE_NUMBER
         AND NVL(XLD.REJECT_SUBINVENTORY_TRF, 'N')  IN ( 'N','E') --V 1.6 
         AND NVL(REJECT_QUANTITY, 0) > 0;
  
    ---------------------------------------------------------------------ADEED BY ARUN ON 28MAR2022
    CURSOR C_RETURN_QTY(P_LINE_NUMBER NUMBER) IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD
       WHERE XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
         AND XLD.COMPLETE_FLAG = 'YES'
         AND XLD.LINE_NUM = P_LINE_NUMBER
         AND NVL(XLD.RETURN_SUBINVENTORY_TRF, 'N') IN ( 'N','E') --V 1.6 
            -- AND NVL (XLD.REJECT_SUBINVENTORY_TRF, 'N') = 'N'
         AND NVL(RETURN_QTY, 0) > 0;
         
         --added for v1.6 
   CURSOR C_LOT (P_INVENTORY_ITEM_ID NUMBER, P_SUBINVENTORY_CODE IN VARCHAR2)
      IS
         SELECT   *
             FROM (SELECT   MLN.LOT_NUMBER, MLN.CREATION_DATE,
                            XXMSSL_LRN_PKG.GET_OHQTY
                                 (MOQ.INVENTORY_ITEM_ID,
                                  MOQ.ORGANIZATION_ID,
                                  MOQ.SUBINVENTORY_CODE,
                                  MLN.LOT_NUMBER,
                                  'ATT'
                                 ) TRANSACTION_QUANTITY
                       FROM MTL_ONHAND_QUANTITIES MOQ, MTL_LOT_NUMBERS MLN
                      WHERE MOQ.ORGANIZATION_ID = MLN.ORGANIZATION_ID
                        AND MOQ.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
                        AND MLN.LOT_NUMBER = MOQ.LOT_NUMBER
                        AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
                        AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
                        AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
                   GROUP BY MLN.LOT_NUMBER,
                            MOQ.INVENTORY_ITEM_ID,
                            MOQ.ORGANIZATION_ID,
                            SUBINVENTORY_CODE,
                            MLN.CREATION_DATE)
            WHERE TRANSACTION_QUANTITY > 0
         ORDER BY CREATION_DATE;
  
    --------------------------------------------------------------------ADEED BY ARUN ON 28MAR2022
  /*-- commented for v1.6
    CURSOR C_LOT(P_INVENTORY_ITEM_ID NUMBER,
                 P_SUBINVENTORY_CODE IN VARCHAR2,
                 P_LINE_NUMBER       NUMBER) IS
      SELECT INVENTORY_ITEM_ID,
             ORGANIZATION_ID,
             LOT_NUMBER,
             LOT_QUANTITY - NVL(COMPLETE_QTY, 0) TRANSACTION_QUANTITY,
             LOT_DATE,
             XXMSSL_LRN_PKG.GET_OHQTY(XXLOT.INVENTORY_ITEM_ID,
                                      XXLOT.ORGANIZATION_ID,
                                      P_SUBINVENTORY_CODE,
                                      XXLOT.LOT_NUMBER,
                                      'ATT' --AVAILABLE TO TRANSACT QTY
                                      ) ON_HAND
        FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT_GTT XXLOT
       WHERE XXLOT.LRN_NO = P_LRN_NUMBER
         AND XXLOT.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
         AND XXLOT.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XXLOT.LINE_NUMBER = P_LINE_NUMBER
         AND LOT_QUANTITY - NVL(XXLOT.COMPLETE_QTY, 0) > 0
       ORDER BY LOT_DATE;
  
    CURSOR C_LOT_MAIN(P_INVENTORY_ITEM_ID NUMBER,
                      P_SUBINVENTORY_CODE IN VARCHAR2,
                      P_LINE_NUMBER       NUMBER) IS
      SELECT XXLOT.INVENTORY_ITEM_ID,
             MLN.CREATION_DATE,
             XXLOT.ORGANIZATION_ID,
             XXLOT.SUBINVENTORY_CODE,
             XXLOT.LOT_NUMBER,
             SUM(XXLOT.LOT_QUANTITY) LOT_QUANTITY,
             XXMSSL_LRN_PKG.GET_OHQTY(XXLOT.INVENTORY_ITEM_ID,
                                      XXLOT.ORGANIZATION_ID,
                                      P_SUBINVENTORY_CODE,
                                      XXLOT.LOT_NUMBER,
                                      'ATT' --AVAILABLE TO TRANSACT QTY
                                      ) ON_HAND
        FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT, MTL_LOT_NUMBERS MLN
       WHERE 1 = 1
         AND XXLOT.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
         AND XXLOT.ORGANIZATION_ID = MLN.ORGANIZATION_ID
         AND XXLOT.LOT_NUMBER = MLN.LOT_NUMBER
         AND XXLOT.LRN_NO = P_LRN_NUMBER
         AND XXLOT.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
         AND XXLOT.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XXLOT.LINE_NUMBER = P_LINE_NUMBER
         AND XXLOT.SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
       GROUP BY XXLOT.INVENTORY_ITEM_ID,
                XXLOT.ORGANIZATION_ID,
                XXLOT.LOT_NUMBER,
                XXLOT.SUBINVENTORY_CODE,
                MLN.CREATION_DATE
       ORDER BY MLN.CREATION_DATE;
    /* SELECT   LOT_NUMBER, DATE_RECEIVED,     ----CMMENTED BY YASHWANT ON 10-JUN-2019
             SUM (TRANSACTION_QUANTITY) TRANSACTION_QUANTITY
        FROM MTL_ONHAND_QUANTITIES
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
         AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
    GROUP BY LOT_NUMBER, DATE_RECEIVED
    ORDER BY DATE_RECEIVED;*/ --COMMENT BY YASHWANT ON 23-JUL-2019
    /* SELECT   MOQ.LOT_NUMBER, MOQ.DATE_RECEIVED,
             SUM (MOQ.TRANSACTION_QUANTITY) TRANSACTION_QUANTITY,
             SUM(XXLOT.LOT_QUANTITY) LOT_QTY
        FROM MTL_ONHAND_QUANTITIES MOQ,
             XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT
       WHERE MOQ.LOT_NUMBER        = XXLOT.LOT_NUMBER
         AND MOQ.ORGANIZATION_ID   = XXLOT.ORGANIZATION_ID
         AND MOQ.INVENTORY_ITEM_ID = XXLOT.INVENTORY_ITEM_ID
         AND XXLOT.LRN_NO          = P_LRN_NUMBER
         AND XXLOT.LINE_NUMBER     = P_LINE_NUMBER
         AND MOQ.ORGANIZATION_ID   = P_ORGANIZATION_ID
         AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
         AND MOQ.SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
    GROUP BY MOQ.LOT_NUMBER, MOQ.DATE_RECEIVED
    ORDER BY MOQ.DATE_RECEIVED;*/
  
    CURSOR C_MAIL IS
      SELECT XLH.TRANSACTION_TYPE,
             XLH.CREATED_BY,
             XLH.APPROVED_BY,
             XLH.LRN_STATUS
        FROM XXMSSL.XXMSSL_LRN_HEADER_T XLH
       WHERE XLH.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLH.LRN_NO = P_LRN_NUMBER;
  
  BEGIN
  
     G_LRN_NO := P_LRN_NUMBER;
    G_ACTION := 'QUALITY_SUBINVENTORY_TRF';
   
    BEGIN
      SELECT OPERATING_UNIT
        INTO L_OU
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_OU := NULL;
    END;
  
    BEGIN
      SELECT TRANSACTION_TYPE
        INTO L_TRAN_TYPE
        FROM XXMSSL_LRN_HEADER_T
       WHERE LRN_NO = P_LRN_NUMBER
         AND ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRAN_TYPE := NULL;
    END;
  
    L_SUBINVENTORY_CNT  := 0;
    L_FROM_SUBINVENTORY := NULL;
  
    IF L_TRAN_TYPE = 'MRN' ---VIKAS
     THEN
      L_FROM_SUBINVENTORY := FND_PROFILE.VALUE('XXMSSL_MRN_LOCATION');
    ELSE
      L_FROM_SUBINVENTORY := 'MR001';
    END IF;
  
    BEGIN
      SELECT COUNT(1)
        INTO L_SUBINVENTORY_CNT
        FROM MTL_SECONDARY_INVENTORIES MSI
       WHERE -1 = -1
         AND UPPER(MSI.SECONDARY_INVENTORY_NAME) =
             UPPER(L_FROM_SUBINVENTORY)
         AND MSI.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND NVL(MSI.DISABLE_DATE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE);
    EXCEPTION
      WHEN OTHERS THEN
        L_SUBINVENTORY_CNT := 0;
    END;
  
    IF L_SUBINVENTORY_CNT = 0 THEN
    
      PRINT_LOG('Error:From Sub-inventory Does Not Exist In System:-  ' ||
                L_FROM_SUBINVENTORY);
      RETURN;
    END IF;
  
    --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
  
    BEGIN
      SELECT DECODE(L_TRAN_TYPE,
                    'LRN',
                    'LRN Subinventory Transfer',
                    'MRN',
                    'MRN')
        INTO L_TYPE
        FROM DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        L_TYPE := NULL;
    END; --ADDED BY DALJEET ON 30-NOV-2020 FOR IDACS
  
 
    MO_GLOBAL.SET_POLICY_CONTEXT('S', L_OU);
    INV_GLOBALS.SET_ORG_ID(P_ORGANIZATION_ID);
    MO_GLOBAL.INIT('INV');
    PRINT_LOG('<----------- Starting Quality Subinventory Transfer Process ------------>');
    PRINT_LOG('p_lrn_number :- ' || P_LRN_NUMBER);
  
    /**************** GET TRANSACTION TYPE ***************************/
    BEGIN
      SELECT TRANSACTION_TYPE_ID
        INTO L_TRANSACTION_TYPE_ID
        FROM MTL_TRANSACTION_TYPES
       WHERE TRANSACTION_TYPE_NAME =
             DECODE(L_TRAN_TYPE, 'LRN', 'LRN Transfers', 'MRN', 'MRN')
         AND TRANSACTION_SOURCE_TYPE_ID = 13;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRANSACTION_TYPE_ID := NULL;
    END;
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      PRINT_LOG('Transaction Type ''LRN Transfers/MRN'' is not Defined');
      RETURN;
    END IF;
  
    /**************************** CHECK PERIOD IS OPEN ****************/
    SELECT COUNT(1)
      INTO L_COUNT
      FROM ORG_ACCT_PERIODS_V
     WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
       AND TRUNC(SYSDATE) BETWEEN START_DATE AND END_DATE
       AND UPPER(STATUS) = 'OPEN';
  
    IF L_COUNT = 0 THEN
      PRINT_LOG('Error : Period is Not Open');
      RETURN;
    END IF;
  
   -- PRINT_LOG('insert into xxmssl.xxmssl_lrn_subinv_lot_gtt');
  
   
  
  /*  comment for v 1.5 
    INSERT INTO XXMSSL.XXMSSL_LRN_SUBINV_LOT_GTT
      (INVENTORY_ITEM_ID,
       LOT_DATE,
       ORGANIZATION_ID,
       LOT_NUMBER,
       LOT_QUANTITY,
       LINE_NUMBER,
       LRN_NO)
      SELECT XXLOT.INVENTORY_ITEM_ID,
             MLN.CREATION_DATE,
             XXLOT.ORGANIZATION_ID,
             XXLOT.LOT_NUMBER,
             SUM(XXLOT.LOT_QUANTITY) LOT_QUANTITY,
             XXLOT.LINE_NUMBER,
             P_LRN_NUMBER
        FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT, MTL_LOT_NUMBERS MLN
       WHERE 1 = 1
         AND XXLOT.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
         AND XXLOT.ORGANIZATION_ID = MLN.ORGANIZATION_ID
         AND XXLOT.LOT_NUMBER = MLN.LOT_NUMBER
         AND XXLOT.LRN_NO = P_LRN_NUMBER
            --AND XXLOT.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
         AND XXLOT.ORGANIZATION_ID = P_ORGANIZATION_ID
      -- AND XXLOT.LINE_NUMBER       = P_LINE_NUMBER
      --AND XXLOT.SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
       GROUP BY XXLOT.INVENTORY_ITEM_ID,
                XXLOT.ORGANIZATION_ID,
                XXLOT.LOT_NUMBER,
                XXLOT.LINE_NUMBER,
                MLN.CREATION_DATE
       ORDER BY MLN.CREATION_DATE;*/
  
    --PRINT_LOG('end into xxmssl.xxmssl_lrn_subinv_lot_gtt');
  
    FOR R_MAIN IN C_MAIN LOOP
    
      BEGIN
        SELECT MSI.SECONDARY_INVENTORY_NAME
          INTO L_TO_SUBINVENTORY
          FROM FND_LOOKUP_VALUES            FLV,
               ORG_ORGANIZATION_DEFINITIONS OOD,
               MTL_SECONDARY_INVENTORIES    MSI
         WHERE LOOKUP_TYPE = 'MSSL_LRN_SCRAP_SUBINVENTORY'
           AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
           AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
           AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
           AND FLV.ENABLED_FLAG = 'Y'
           AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE)
           AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
           AND ROWNUM = 1;
      EXCEPTION
        WHEN OTHERS THEN
          L_TO_SUBINVENTORY := NULL;
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'Error : No Subinventory Defined in lookup ''MSSL_LRN_SCRAP_SUBINVENTORY'' For Scrap Subinventory Transfer');
      END;
    
      PRINT_LOG('scrap subinv l_to_subinventory ' || L_TO_SUBINVENTORY);
      PRINT_LOG(' main cursor inventory_item_id :-  ' ||
                R_MAIN.INVENTORY_ITEM_ID);
      PRINT_LOG('line_num ' || R_MAIN.LINE_NUM);
      
      --delete already exsist interface recodrs before insert into interface table V 1.6 
              BEGIN
              DELETE 
              FROM   MTL_TRANSACTION_LOTS_INTERFACE 
              WHERE TRANSACTION_INTERFACE_ID in ( SELECT TRANSACTION_INTERFACE_ID
                                                   FROM   MTL_TRANSACTIONS_INTERFACE  
                                                  WHERE TRANSACTION_REFERENCE = R_MAIN.lrn_no
                                                  AND organization_id = R_MAIN.organization_id
                                                  AND inventory_item_id =  R_MAIN.inventory_item_id
                                                  AND SUBINVENTORY_CODE = L_FROM_SUBINVENTORY);
                
               DELETE FROM   MTL_TRANSACTIONS_INTERFACE  
               WHERE TRANSACTION_REFERENCE = R_MAIN.lrn_no
               AND organization_id         = R_MAIN.organization_id
               AND inventory_item_id       =  R_MAIN.inventory_item_id
               AND SUBINVENTORY_CODE       =  L_FROM_SUBINVENTORY;
               
              EXCEPTION WHEN 
                  OTHERS THEN 
                 PRINT_LOG('error while delete record from interface table '||sqlerrm);
             END ;
             
          
        
      
              
      IF L_TO_SUBINVENTORY IS NOT NULL THEN
        PRINT_LOG('start scrap sbinv loop ');
      
        FOR V_SCRAP_QTY IN C_SCRAP_QTY(R_MAIN.LINE_NUM) 
         LOOP
         
          L_RETURN_STATUS := NULL;
          L_MSG_CNT       := NULL;
          L_MSG_DATA      := NULL;
          L_TRANS_COUNT   := NULL;
          PRINT_LOG('scrap inventory_item_id :-  ' ||
                    V_SCRAP_QTY.INVENTORY_ITEM_ID);
          PRINT_LOG('scrapped_quantity :-  ' ||
                    V_SCRAP_QTY.SCRAPPED_QUANTITY);
        
          SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
            INTO L_TRANSACTION_INTERFACE_ID
            FROM DUAL;
        
          PRINT_LOG('start insert into mtl_transactions_interface ');
        
          INSERT INTO MTL_TRANSACTIONS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_SCRAP_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --                            'LRN SUBINVENTORY TRANSFER',--COMENT OUT BY DALJEET ON 30-NOV-2020  FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 30-NOV-2020  FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_SCRAP_QTY.SCRAPPED_QUANTITY,
             L_TRANSACTION_TYPE_ID,
             V_SCRAP_QTY.UOM,
             L_TO_SUBINVENTORY,
             'SCRAP',
             P_LRN_NUMBER,
             V_SCRAP_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_SCRAP_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --                            'LRN SUBINVENTORY TRANSFER',--COMENT OUT BY DALJEET ON 30-NOV-2020  FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 30-NOV-2020  FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_SCRAP_QTY.SCRAPPED_QUANTITY,
             L_TRANSACTION_TYPE_ID,
             V_SCRAP_QTY.UOM,
             L_TO_SUBINVENTORY,
             'SCRAP',
             P_LRN_NUMBER,
             V_SCRAP_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          PRINT_LOG('end insert into mtl_transactions_interface ');
        
          /***************** CHECK ITEM IS LOT CONTROLLED ***************/
          SELECT COUNT(1)
            INTO L_COUNT
            FROM MTL_SYSTEM_ITEMS_B
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND INVENTORY_ITEM_ID = V_SCRAP_QTY.INVENTORY_ITEM_ID
             AND LOT_CONTROL_CODE = 2;
        
          IF L_COUNT > 0 THEN
            L_REMAINING_QUANTITY := V_SCRAP_QTY.SCRAPPED_QUANTITY;
          
           
                --     comment for v 1.6 
                --      FOR V_LOT IN C_LOT(V_SCRAP_QTY.INVENTORY_ITEM_ID,
                --                               L_FROM_SUBINVENTORY,
                --                               V_SCRAP_QTY.LINE_NUM)
                                                
             FOR V_LOT IN C_LOT(V_SCRAP_QTY.INVENTORY_ITEM_ID,
                                 L_FROM_SUBINVENTORY) 
             LOOP
                
              PRINT_LOG('start insert into mtl_transaction_lots_interface ');
              L_TRANSACTION_QUANTITY := NULL;
            
              IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
                L_REMAINING_QUANTITY   := 0;
              ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
                L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                          V_LOT.TRANSACTION_QUANTITY;
              END IF;
            
              PRINT_LOG('lot_quantity  ' || V_LOT.TRANSACTION_QUANTITY);
              PRINT_LOG('v_lot.lot_number  ' || V_LOT.LOT_NUMBER);
              PRINT_LOG('l_transaction_quantity  ' ||
                        L_TRANSACTION_QUANTITY);
            
              INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
                (TRANSACTION_INTERFACE_ID,
                 LOT_NUMBER,
                 TRANSACTION_QUANTITY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATED_BY,
                 CREATION_DATE,
                 CREATED_BY)
              VALUES
                (L_TRANSACTION_INTERFACE_ID,
                 V_LOT.LOT_NUMBER,
                 L_TRANSACTION_QUANTITY,
                 SYSDATE,
                 L_USER_ID,
                 SYSDATE,
                 L_USER_ID);
            
              PRINT_LOG('insert into xxmssl_lrn_subinv_lot_gtt ');
            
              /*-- comment for V1.6 
              UPDATE XXMSSL.XXMSSL_LRN_SUBINV_LOT_GTT
                 SET COMPLETE_QTY =
                     (NVL(COMPLETE_QTY, 0) + L_TRANSACTION_QUANTITY)
               WHERE LRN_NO = P_LRN_NUMBER
                 AND INVENTORY_ITEM_ID = V_SCRAP_QTY.INVENTORY_ITEM_ID
                 AND ORGANIZATION_ID = P_ORGANIZATION_ID
                 AND LINE_NUMBER = V_SCRAP_QTY.LINE_NUM
                 AND LOT_NUMBER = V_LOT.LOT_NUMBER;*/
            
              PRINT_LOG('----------------------------------------------------------------------------------------------------- ');
            
              IF L_REMAINING_QUANTITY = 0 THEN
                EXIT;
              END IF;
            END LOOP;
          END IF;
        
          PRINT_LOG('start inv_txn_manager_pub.process_transactions API ');
          ---  COMMIT;
          V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                                P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                                P_COMMIT           => FND_API.G_TRUE,
                                                                P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                                X_RETURN_STATUS    => L_RETURN_STATUS,
                                                                X_MSG_COUNT        => L_MSG_CNT,
                                                                X_MSG_DATA         => L_MSG_DATA,
                                                                X_TRANS_COUNT      => L_TRANS_COUNT,
                                                                P_TABLE            => 1,
                                                                P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
          PRINT_LOG('end inv_txn_manager_pub.process_transactions API ');
          PRINT_LOG('l_return_status :-  ' || L_RETURN_STATUS);
          PRINT_LOG('l_msg_cnt :-  ' || L_MSG_CNT);
        
          IF (NVL(L_RETURN_STATUS, 'E') <> 'S') THEN
            L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
          
            FOR I IN 1 .. L_MSG_CNT LOOP
              FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                              P_ENCODED       => 'F',
                              P_DATA          => L_MSG_DATA,
                              P_MSG_INDEX_OUT => X_MSG_INDEX);
              X_MSG := X_MSG || '.' || L_MSG_DATA;
            END LOOP;
          
            PRINT_LOG('Error in Subinventory Transfer:' || X_MSG);
            
             BEGIN
                        SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
                          INTO L_INTERFACE_ERROR
                          FROM MTL_TRANSACTIONS_INTERFACE
                         WHERE TRANSACTION_INTERFACE_ID =
                                                    L_TRANSACTION_INTERFACE_ID
                           AND SOURCE_CODE = L_TYPE;
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           L_INTERFACE_ERROR := NULL;
                     END;
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET SCRAP_SUBINVENTORY_TRF = 'E',
                   ERROR_MESSAGE          = SUBSTR(ERROR_MESSAGE ||
                                                   ' SCRAP:l_transaction_interface_id ' ||
                                                   L_TRANSACTION_INTERFACE_ID ||
                                                   L_INTERFACE_ERROR,
                                                   1,
                                                   2000)
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND LINE_NUM = V_SCRAP_QTY.LINE_NUM
               AND NVL(SCRAPPED_QUANTITY, 0) > 0;
               
          ELSIF NVL(L_RETURN_STATUS, 'E') = 'S' THEN
          
            PRINT_LOG('Subinventory Transfer Successful');
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET SCRAP_SUBINVENTORY_TRF = 'Y'
                  ,ERROR_MESSAGE = NULL
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND LINE_NUM = V_SCRAP_QTY.LINE_NUM
               AND NVL(SCRAPPED_QUANTITY, 0) > 0;
          
            PRINT_LOG('start lrn_scarp_issue process');
            
            LRN_SCARP_ISSUE(ERRBUF,
                            RETCODE,
                            P_ORGANIZATION_ID,
                            P_LRN_NUMBER,
                            L_TO_SUBINVENTORY,
                            V_SCRAP_QTY.INVENTORY_ITEM_ID,
                            V_SCRAP_QTY.LINE_NUM);
                            
            PRINT_LOG('end lrn_scarp_issue process');
            
          END IF;
        END LOOP;
      
        --- COMMIT;
        PRINT_LOG('end  scrap subinv loop');
      END IF;
    
      PRINT_LOG('start reject subinv  loop');
    
      --      IF L_TO_SUBINVENTORY IS NOT NULL
      --      THEN
      FOR V_REJECT_QTY IN C_REJECT_QTY(R_MAIN.LINE_NUM) LOOP
      
        L_RETURN_STATUS := NULL;
        L_MSG_CNT       := NULL;
        L_MSG_DATA      := NULL;
        L_TRANS_COUNT   := NULL;
        PRINT_LOG('reject inventory_item_id :-  ' ||
                  V_REJECT_QTY.INVENTORY_ITEM_ID);
        PRINT_LOG('reject_quantity :-  ' || V_REJECT_QTY.REJECT_QUANTITY);
      
        BEGIN
          SELECT MC.SEGMENT2
            INTO L_SEGMENT2
            FROM MTL_ITEM_CATEGORIES MIC, MTL_CATEGORIES MC
           WHERE MIC.CATEGORY_SET_ID = 1
             AND MIC.CATEGORY_ID = MC.CATEGORY_ID
             AND MIC.ORGANIZATION_ID = P_ORGANIZATION_ID
             AND MIC.INVENTORY_ITEM_ID = V_REJECT_QTY.INVENTORY_ITEM_ID;
        EXCEPTION
          WHEN OTHERS THEN
            L_SEGMENT2 := NULL;
        END;
      
        PRINT_LOG('l_segment2 :-  ' || L_SEGMENT2);
        /***************************** SUBINVENTORY TRANSFER FOR REJECT QTY **********************/
        L_TO_SUBINVENTORY := NULL;
      
        BEGIN
          /*SELECT MSI.SECONDARY_INVENTORY_NAME
           INTO L_TO_SUBINVENTORY
           FROM FND_LOOKUP_VALUES FLV,
                ORG_ORGANIZATION_DEFINITIONS OOD,
                MTL_SECONDARY_INVENTORIES MSI
          WHERE LOOKUP_TYPE = 'MSSL_LRN_REJECT_SUBINVENTORY'
            AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
            AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
            AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
            AND FLV.ENABLED_FLAG = 'Y'
            AND NVL (FLV.START_DATE_ACTIVE, TRUNC (SYSDATE)) <=
                                                               TRUNC (SYSDATE)
            AND NVL (FLV.END_DATE_ACTIVE, TRUNC (SYSDATE)) >= TRUNC (SYSDATE)
            AND ROWNUM = 1;*/
          SELECT MSI.SECONDARY_INVENTORY_NAME
            INTO L_TO_SUBINVENTORY
            FROM FND_LOOKUP_VALUES FLV, MTL_SECONDARY_INVENTORIES MSI
           WHERE LOOKUP_TYPE = 'XXMSSL_QA_DEFAULT_INSP_SUB_INV'
             AND FLV.MEANING = L_SEGMENT2
             AND MSI.SECONDARY_INVENTORY_NAME = FLV.ATTRIBUTE2
             AND FLV.ENABLED_FLAG = 'Y'
             AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                 TRUNC(SYSDATE)
             AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
             AND ROWNUM = 1;
        
          PRINT_LOG('l_to_subinventory :-  ' || L_TO_SUBINVENTORY);
        EXCEPTION
          WHEN OTHERS THEN
            L_TO_SUBINVENTORY := NULL;
            PRINT_LOG('Error : No Subinventory Defined in lookup ''XXMSSL_QA_DEFAULT_INSP_SUB_INV'' For Reject Subinventory Transfer');
        END;
      
        IF L_TO_SUBINVENTORY IS NOT NULL THEN
          SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
            INTO L_TRANSACTION_INTERFACE_ID
            FROM DUAL;
        
          PRINT_LOG('start insert into mtl_transactions_interface');
        
          INSERT INTO MTL_TRANSACTIONS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_REJECT_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --'LRN SUBINVENTORY TRANSFER'--COMMENT OUT BY DALJEET ON 20-NOV-2020 FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 20-NOV-2020 FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_REJECT_QTY.REJECT_QUANTITY,
             L_TRANSACTION_TYPE_ID,
             V_REJECT_QTY.UOM,
             L_TO_SUBINVENTORY,
             'REJECT',
             P_LRN_NUMBER,
             V_REJECT_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_REJECT_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --                            'LRN SUBINVENTORY TRANSFER', --COMMENT OUT BY DALJEET ON 20-NOV-2020 FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 20-NOV-2020 FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_REJECT_QTY.REJECT_QUANTITY,
             L_TRANSACTION_TYPE_ID,
             V_REJECT_QTY.UOM,
             L_TO_SUBINVENTORY,
             'REJECT',
             P_LRN_NUMBER,
             V_REJECT_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          PRINT_LOG('end insert into mtl_transactions_interface ');
        
          /***************** CHECK ITEM IS LOT CONTROLLED ***************/
          SELECT COUNT(1)
            INTO L_COUNT
            FROM MTL_SYSTEM_ITEMS_B
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND INVENTORY_ITEM_ID = V_REJECT_QTY.INVENTORY_ITEM_ID
             AND LOT_CONTROL_CODE = 2;
        
          IF L_COUNT > 0 THEN
            L_REMAINING_QUANTITY := V_REJECT_QTY.REJECT_QUANTITY;
          
            --            comment for  v 1.6 
            --FOR V_LOT IN C_LOT(V_REJECT_QTY.INVENTORY_ITEM_ID,
            --                               L_FROM_SUBINVENTORY,
            --                               V_REJECT_QTY.LINE_NUM) 
                               
             FOR V_LOT IN C_LOT (V_REJECT_QTY.INVENTORY_ITEM_ID,
                               L_FROM_SUBINVENTORY
                               )
             LOOP
              PRINT_LOG('start insert into mtl_transaction_lots_interface ');
              L_TRANSACTION_QUANTITY := NULL;
            
              IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
                L_REMAINING_QUANTITY   := 0;
              ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
                L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                          V_LOT.TRANSACTION_QUANTITY;
              END IF;
            
              PRINT_LOG('lot_quantity  ' || V_LOT.TRANSACTION_QUANTITY);
              PRINT_LOG('v_lot.lot_number  ' || V_LOT.LOT_NUMBER);
              PRINT_LOG('l_transaction_quantity  ' ||
                        L_TRANSACTION_QUANTITY);
            
              INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
                (TRANSACTION_INTERFACE_ID,
                 LOT_NUMBER,
                 TRANSACTION_QUANTITY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATED_BY,
                 CREATION_DATE,
                 CREATED_BY)
              VALUES
                (L_TRANSACTION_INTERFACE_ID,
                 V_LOT.LOT_NUMBER,
                 L_TRANSACTION_QUANTITY,
                 SYSDATE,
                 L_USER_ID,
                 SYSDATE,
                 L_USER_ID);
            
              PRINT_LOG('insert into xxmssl_lrn_subinv_lot_gtt ');
              
             ---v 1.6 
--              UPDATE XXMSSL.XXMSSL_LRN_SUBINV_LOT_GTT
--                 SET COMPLETE_QTY =
--                     (NVL(COMPLETE_QTY, 0) + L_TRANSACTION_QUANTITY)
--               WHERE LRN_NO = P_LRN_NUMBER
--                 AND INVENTORY_ITEM_ID = V_REJECT_QTY.INVENTORY_ITEM_ID
--                 AND ORGANIZATION_ID = P_ORGANIZATION_ID
--                 AND LINE_NUMBER = V_REJECT_QTY.LINE_NUM
--                 AND LOT_NUMBER = V_LOT.LOT_NUMBER;
            
              IF L_REMAINING_QUANTITY = 0 THEN
                EXIT;
              END IF;
            END LOOP;
          END IF;
        
          PRINT_LOG('start inv_txn_manager_pub.process_transactions API ');
          ---    COMMIT;
          V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                                P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                                P_COMMIT           => FND_API.G_TRUE,
                                                                P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                                X_RETURN_STATUS    => L_RETURN_STATUS,
                                                                X_MSG_COUNT        => L_MSG_CNT,
                                                                X_MSG_DATA         => L_MSG_DATA,
                                                                X_TRANS_COUNT      => L_TRANS_COUNT,
                                                                P_TABLE            => 1,
                                                                P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
          PRINT_LOG('end inv_txn_manager_pub.process_transactions API ');
          PRINT_LOG('l_return_status :-  ' || L_RETURN_STATUS);
          PRINT_LOG('l_msg_cnt :-  ' || L_MSG_CNT);
        
          IF (NVL(L_RETURN_STATUS, 'E') <> FND_API.G_RET_STS_SUCCESS) THEN
            L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
          
            FOR I IN 1 .. L_MSG_CNT LOOP
              FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                              P_ENCODED       => 'F',
                              P_DATA          => L_MSG_DATA,
                              P_MSG_INDEX_OUT => X_MSG_INDEX);
              X_MSG := X_MSG || '.' || L_MSG_DATA;
            END LOOP;
          
            
            
            BEGIN
                        SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
                          INTO L_INTERFACE_ERROR
                          FROM MTL_TRANSACTIONS_INTERFACE
                         WHERE TRANSACTION_INTERFACE_ID =
                                                    L_TRANSACTION_INTERFACE_ID
                           AND SOURCE_CODE = L_TYPE;
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           L_INTERFACE_ERROR := NULL;
                     END;
                  PRINT_LOG('Error in Reject Subinventory Transfer:' || X_MSG ||' L_INTERFACE_ERROR '||L_INTERFACE_ERROR);
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET REJECT_SUBINVENTORY_TRF = 'E',
                   ERROR_MESSAGE           = SUBSTR(ERROR_MESSAGE ||
                                                    ' REJECT:l_transaction_interface_id ' ||
                                                    L_TRANSACTION_INTERFACE_ID ||
                                                    L_INTERFACE_ERROR,
                                                    1,
                                                    2000)
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND LINE_NUM = V_REJECT_QTY.LINE_NUM
               AND NVL(REJECT_QUANTITY, 0) > 0;
          ELSIF (NVL(L_RETURN_STATUS, 'E') = FND_API.G_RET_STS_SUCCESS) THEN
            PRINT_LOG('Reject Subinventory Transfer Successful');
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET REJECT_SUBINVENTORY_TRF = 'Y'
                    ,ERROR_MESSAGE = NULL
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND LINE_NUM = V_REJECT_QTY.LINE_NUM
               AND NVL(REJECT_QUANTITY, 0) > 0;
          END IF;
        END IF;
      END LOOP;
    
      PRINT_LOG('end  Reject  subinv loop');
      PRINT_LOG('--------------------------------------------------------------------------------------------');
      ---COMMIT;
      ----------------------------------ADDED BY ARUN KUMAR 28MAR2022 -----------------------------------------
      PRINT_LOG('start Return sbinv loop ');
    
      FOR V_RETURN_QTY IN C_RETURN_QTY(R_MAIN.LINE_NUM) LOOP
        L_RETURN_STATUS := NULL;
        L_MSG_CNT       := NULL;
        L_MSG_DATA      := NULL;
        L_TRANS_COUNT   := NULL;
        PRINT_LOG('return inventory_item_id :-  ' ||
                  V_RETURN_QTY.INVENTORY_ITEM_ID);
        PRINT_LOG('return_Qty :-  ' || V_RETURN_QTY.RETURN_QTY);
      
        BEGIN
          SELECT MC.SEGMENT2
            INTO L_SEGMENT2
            FROM MTL_ITEM_CATEGORIES MIC, MTL_CATEGORIES MC
           WHERE MIC.CATEGORY_SET_ID = 1
             AND MIC.CATEGORY_ID = MC.CATEGORY_ID
             AND MIC.ORGANIZATION_ID = P_ORGANIZATION_ID
             AND MIC.INVENTORY_ITEM_ID = V_RETURN_QTY.INVENTORY_ITEM_ID;
        EXCEPTION
          WHEN OTHERS THEN
            L_SEGMENT2 := NULL;
        END;
      
        PRINT_LOG('l_segment2 :-  ' || L_SEGMENT2);
        L_TO_SUBINVENTORY := V_RETURN_QTY.SUBINVENTORY_CODE;
      
        IF L_TO_SUBINVENTORY IS NOT NULL THEN
          SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
            INTO L_TRANSACTION_INTERFACE_ID
            FROM DUAL;
        
          PRINT_LOG('start insert into mtl_transactions_interface');
        
          INSERT INTO MTL_TRANSACTIONS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_RETURN_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --'LRN SUBINVENTORY TRANSFER'--COMMENT OUT BY DALJEET ON 20-NOV-2020 FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 20-NOV-2020 FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_RETURN_QTY.RETURN_QTY,
             L_TRANSACTION_TYPE_ID,
             V_RETURN_QTY.UOM,
             L_TO_SUBINVENTORY,
             'RETURN',
             P_LRN_NUMBER,
             V_RETURN_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_RETURN_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --                            'LRN SUBINVENTORY TRANSFER', --COMMENT OUT BY DALJEET ON 20-NOV-2020 FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 20-NOV-2020 FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_RETURN_QTY.RETURN_QTY,
             L_TRANSACTION_TYPE_ID,
             V_RETURN_QTY.UOM,
             L_TO_SUBINVENTORY,
             'RETURN',
             P_LRN_NUMBER,
             V_RETURN_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          PRINT_LOG('end insert into mtl_transactions_interface ');
        
          /***************** CHECK ITEM IS LOT CONTROLLED ***************/
          SELECT COUNT(1)
            INTO L_COUNT
            FROM MTL_SYSTEM_ITEMS_B
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND INVENTORY_ITEM_ID = V_RETURN_QTY.INVENTORY_ITEM_ID
             AND LOT_CONTROL_CODE = 2;
        
          IF L_COUNT > 0 THEN
            L_REMAINING_QUANTITY := V_RETURN_QTY.RETURN_QTY;
          
            --            comment for  v 1.6 
                --FOR V_LOT IN C_LOT(V_RETURN_QTY.INVENTORY_ITEM_ID,
                --                               L_FROM_SUBINVENTORY,
                --                               V_RETURN_QTY.LINE_NUM) 
                               
             FOR V_LOT IN C_LOT (V_RETURN_QTY.INVENTORY_ITEM_ID,
                               L_FROM_SUBINVENTORY
                               )
             LOOP
              PRINT_LOG('start insert into mtl_transaction_lots_interface ');
              L_TRANSACTION_QUANTITY := NULL;
            
              IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
                L_REMAINING_QUANTITY   := 0;
              ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
                L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                          V_LOT.TRANSACTION_QUANTITY;
              END IF;
            
              PRINT_LOG('lot_quantity  ' || V_LOT.TRANSACTION_QUANTITY);
              PRINT_LOG('v_lot.lot_number  ' || V_LOT.LOT_NUMBER);
              PRINT_LOG('l_transaction_quantity  ' ||
                        L_TRANSACTION_QUANTITY);
            
              INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
                (TRANSACTION_INTERFACE_ID,
                 LOT_NUMBER,
                 TRANSACTION_QUANTITY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATED_BY,
                 CREATION_DATE,
                 CREATED_BY)
              VALUES
                (L_TRANSACTION_INTERFACE_ID,
                 V_LOT.LOT_NUMBER,
                 L_TRANSACTION_QUANTITY,
                 SYSDATE,
                 L_USER_ID,
                 SYSDATE,
                 L_USER_ID);
            
              PRINT_LOG('insert into xxmssl_lrn_subinv_lot_gtt ');
            
                --             v 1.6 
                -- UPDATE XXMSSL.XXMSSL_LRN_SUBINV_LOT_GTT
                --                 SET COMPLETE_QTY =
                --                     (NVL(COMPLETE_QTY, 0) + L_TRANSACTION_QUANTITY)
                --               WHERE LRN_NO = P_LRN_NUMBER
                --                 AND INVENTORY_ITEM_ID = V_RETURN_QTY.INVENTORY_ITEM_ID
                --                 AND ORGANIZATION_ID = P_ORGANIZATION_ID
                --                 AND LINE_NUMBER = V_RETURN_QTY.LINE_NUM
                --                 AND LOT_NUMBER = V_LOT.LOT_NUMBER;
            
              IF L_REMAINING_QUANTITY = 0 THEN
                EXIT;
              END IF;
            END LOOP;
          END IF;
        
          PRINT_LOG('start inv_txn_manager_pub.process_transactions API ');
          ---    COMMIT;
          V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                                P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                                P_COMMIT           => FND_API.G_TRUE,
                                                                P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                                X_RETURN_STATUS    => L_RETURN_STATUS,
                                                                X_MSG_COUNT        => L_MSG_CNT,
                                                                X_MSG_DATA         => L_MSG_DATA,
                                                                X_TRANS_COUNT      => L_TRANS_COUNT,
                                                                P_TABLE            => 1,
                                                                P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
          PRINT_LOG('end inv_txn_manager_pub.process_transactions API ');
          PRINT_LOG('l_return_status :-  ' || L_RETURN_STATUS);
          PRINT_LOG('l_msg_cnt :-  ' || L_MSG_CNT);
        
          IF (NVL(L_RETURN_STATUS, 'E') <> FND_API.G_RET_STS_SUCCESS) THEN
            L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
          
            FOR I IN 1 .. L_MSG_CNT LOOP
              FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                              P_ENCODED       => 'F',
                              P_DATA          => L_MSG_DATA,
                              P_MSG_INDEX_OUT => X_MSG_INDEX);
              X_MSG := X_MSG || '.' || L_MSG_DATA;
            END LOOP;
            
            BEGIN
                        SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
                          INTO L_INTERFACE_ERROR
                          FROM MTL_TRANSACTIONS_INTERFACE
                         WHERE TRANSACTION_INTERFACE_ID =
                                                    L_TRANSACTION_INTERFACE_ID
                           AND SOURCE_CODE = L_TYPE;
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           L_INTERFACE_ERROR := NULL;
                     END;
          
            PRINT_LOG('Error in Return Subinventory Transfer:' || X_MSG||'  '||L_INTERFACE_ERROR);
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET RETURN_SUBINVENTORY_TRF = 'E',
                   ERROR_MESSAGE           = SUBSTR(ERROR_MESSAGE ||
                                                    ' RETURN:l_transaction_interface_id ' ||
                                                    L_TRANSACTION_INTERFACE_ID ||
                                                    L_INTERFACE_ERROR,
                                                    1,
                                                    2000)
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND LINE_NUM = V_RETURN_QTY.LINE_NUM
               AND NVL(RETURN_QTY, 0) > 0;
          ELSIF (NVL(L_RETURN_STATUS, 'E') = FND_API.G_RET_STS_SUCCESS) THEN
            PRINT_LOG('Return Subinventory Transfer Successful');
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET RETURN_SUBINVENTORY_TRF = 'Y'
                ,ERROR_MESSAGE = NULL
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND LINE_NUM = V_RETURN_QTY.LINE_NUM
               AND NVL(RETURN_QTY, 0) > 0;
          END IF;
        END IF;
      END LOOP;
    
      PRINT_LOG('end  Return  subinv loop');
      PRINT_LOG('--------------------------------------------------------------------------------------------');
      ---------------------------------ADDED BY ARUN KUMAR 28MAR2022 ------------------------------------------
      PRINT_LOG('start store sbinv loop ');
    
      FOR V_STORE_QTY IN C_STORE_QTY(R_MAIN.LINE_NUM) LOOP
        L_RETURN_STATUS := NULL;
        L_MSG_CNT       := NULL;
        L_MSG_DATA      := NULL;
        L_TRANS_COUNT   := NULL;
        PRINT_LOG('store inventory_item_id :-  ' ||
                  V_STORE_QTY.INVENTORY_ITEM_ID);
        PRINT_LOG('store_quantity :-  ' ||
                  V_STORE_QTY.QTY_RETURN_TO_STORES);
      
        BEGIN
          SELECT MC.SEGMENT2
            INTO L_SEGMENT2
            FROM MTL_ITEM_CATEGORIES MIC, MTL_CATEGORIES MC
           WHERE MIC.CATEGORY_SET_ID = 1
             AND MIC.CATEGORY_ID = MC.CATEGORY_ID
             AND MIC.ORGANIZATION_ID = P_ORGANIZATION_ID
             AND MIC.INVENTORY_ITEM_ID = V_STORE_QTY.INVENTORY_ITEM_ID;
        EXCEPTION
          WHEN OTHERS THEN
            L_SEGMENT2 := NULL;
        END;
      
        PRINT_LOG('l_segment2 :-  ' || L_SEGMENT2);
      
        /********************* TO SUBINVENTORY FOR STORE *******************/
        BEGIN
          --COMMENTED ON 20APR2015 AS SUGGESTED BY AMIT
          /*SELECT MSI.SECONDARY_INVENTORY_NAME
           INTO L_TO_SUBINVENTORY
           FROM FND_LOOKUP_VALUES FLV,
                ORG_ORGANIZATION_DEFINITIONS OOD,
                MTL_SECONDARY_INVENTORIES MSI
          WHERE LOOKUP_TYPE = 'MSSL_LRN_STORE_SUBINVENTORY'
            AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
            AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
            AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
            AND FLV.ENABLED_FLAG = 'Y'
            AND NVL (FLV.START_DATE_ACTIVE, TRUNC (SYSDATE)) <=
                                                               TRUNC (SYSDATE)
            AND NVL (FLV.END_DATE_ACTIVE, TRUNC (SYSDATE)) >= TRUNC (SYSDATE)
            AND ROWNUM = 1;*/
          SELECT MSI.SECONDARY_INVENTORY_NAME
            INTO L_TO_SUBINVENTORY
            FROM FND_LOOKUP_VALUES FLV, MTL_SECONDARY_INVENTORIES MSI
           WHERE LOOKUP_TYPE = 'XXMSSL_QA_DEFAULT_INSP_SUB_INV'
             AND FLV.MEANING = L_SEGMENT2
             AND MSI.SECONDARY_INVENTORY_NAME = FLV.ATTRIBUTE1
             AND FLV.ENABLED_FLAG = 'Y'
             AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                 TRUNC(SYSDATE)
             AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
             AND ROWNUM = 1;
        EXCEPTION
          WHEN OTHERS THEN
            L_TO_SUBINVENTORY := NULL;
            PRINT_LOG('Error : No Subinventory Defined in lookup ''XXMSSL_QA_DEFAULT_INSP_SUB_INV'' For Store Subinventory Transfer');
        END;
      
        PRINT_LOG('l_to_subinventory :-  ' || L_TO_SUBINVENTORY);
      
        IF L_TO_SUBINVENTORY IS NOT NULL THEN
          SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
            INTO L_TRANSACTION_INTERFACE_ID
            FROM DUAL;
        
          PRINT_LOG('start insert into mtl_transactions_interface ');
        
          INSERT INTO MTL_TRANSACTIONS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_STORE_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --                            'LRN SUBINVENTORY TRANSFER', --COMMENT OUT BY DALJEET ON 20-NOV-2020 FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 20-NOV-2020 FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_STORE_QTY.QTY_RETURN_TO_STORES,
             L_TRANSACTION_TYPE_ID,
             V_STORE_QTY.UOM,
             L_TO_SUBINVENTORY,
             'STORE',
             P_LRN_NUMBER,
             V_STORE_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
            (CREATED_BY,
             CREATION_DATE,
             INVENTORY_ITEM_ID,
             LAST_UPDATED_BY,
             LAST_UPDATE_DATE,
             LAST_UPDATE_LOGIN,
             LOCK_FLAG,
             ORGANIZATION_ID,
             PROCESS_FLAG,
             SOURCE_CODE,
             SOURCE_HEADER_ID,
             SOURCE_LINE_ID,
             SUBINVENTORY_CODE,
             TRANSACTION_DATE,
             TRANSACTION_HEADER_ID,
             TRANSACTION_INTERFACE_ID,
             TRANSACTION_MODE,
             TRANSACTION_QUANTITY,
             TRANSACTION_TYPE_ID,
             TRANSACTION_UOM,
             TRANSFER_SUBINVENTORY,
             ATTRIBUTE13,
             ATTRIBUTE14,
             ATTRIBUTE15,
             TRANSACTION_REFERENCE)
          VALUES
            (L_USER_ID,
             SYSDATE,
             V_STORE_QTY.INVENTORY_ITEM_ID,
             L_USER_ID,
             SYSDATE,
             L_LOGIN_ID,
             2,
             P_ORGANIZATION_ID,
             1,
             --                            'LRN SUBINVENTORY TRANSFER',--COMMENT OUT BY DALJEET ON 20-NOV-2020 FOR IDACS
             L_TYPE,
             --ADDED BY DALJEET ON 20-NOV-2020 FOR IDACS
             1,
             2,
             L_FROM_SUBINVENTORY,
             SYSDATE,
             L_TRANSACTION_INTERFACE_ID,
             L_TRANSACTION_INTERFACE_ID,
             3,
             V_STORE_QTY.QTY_RETURN_TO_STORES,
             L_TRANSACTION_TYPE_ID,
             V_STORE_QTY.UOM,
             L_TO_SUBINVENTORY,
             'STORE',
             P_LRN_NUMBER,
             V_STORE_QTY.LINE_NUM,
             P_LRN_NUMBER);
        
          PRINT_LOG('end insert into mtl_transactions_interface ');
        
          /***************** CHECK ITEM IS LOT CONTROLLED ***************/
          SELECT COUNT(1)
            INTO L_COUNT
            FROM MTL_SYSTEM_ITEMS_B
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND INVENTORY_ITEM_ID = V_STORE_QTY.INVENTORY_ITEM_ID
             AND LOT_CONTROL_CODE = 2;
        
          IF L_COUNT > 0 THEN
            L_REMAINING_QUANTITY := V_STORE_QTY.QTY_RETURN_TO_STORES;
          
            --            comment for  v 1.6 
            --     FOR V_LOT IN C_LOT(V_STORE_QTY.INVENTORY_ITEM_ID,
            --                               L_FROM_SUBINVENTORY,
            --                               V_STORE_QTY.LINE_NUM) 
                               
             FOR V_LOT IN C_LOT (V_STORE_QTY.INVENTORY_ITEM_ID,
                               L_FROM_SUBINVENTORY
                               )
                       LOOP
              PRINT_LOG('start insert into mtl_transaction_lots_interface ');
              L_TRANSACTION_QUANTITY := NULL;
            
              IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
                L_REMAINING_QUANTITY   := 0;
              ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
                L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                          V_LOT.TRANSACTION_QUANTITY;
              END IF;
            
              PRINT_LOG('lot_quantity  ' || V_LOT.TRANSACTION_QUANTITY);
              PRINT_LOG('v_lot.lot_number  ' || V_LOT.LOT_NUMBER);
              PRINT_LOG('l_transaction_quantity  ' ||
                        L_TRANSACTION_QUANTITY);
            
              INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
                (TRANSACTION_INTERFACE_ID,
                 LOT_NUMBER,
                 TRANSACTION_QUANTITY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATED_BY,
                 CREATION_DATE,
                 CREATED_BY)
              VALUES
                (L_TRANSACTION_INTERFACE_ID,
                 V_LOT.LOT_NUMBER,
                 L_TRANSACTION_QUANTITY,
                 SYSDATE,
                 L_USER_ID,
                 SYSDATE,
                 L_USER_ID);
            
              PRINT_LOG('insert into xxmssl_lrn_subinv_lot_gtt ');
              --v 1.6
--              UPDATE XXMSSL.XXMSSL_LRN_SUBINV_LOT_GTT
--                 SET COMPLETE_QTY =
--                     (NVL(COMPLETE_QTY, 0) + L_TRANSACTION_QUANTITY)
--               WHERE LRN_NO = P_LRN_NUMBER
--                 AND INVENTORY_ITEM_ID = V_STORE_QTY.INVENTORY_ITEM_ID
--                 AND ORGANIZATION_ID = P_ORGANIZATION_ID
--                 AND LINE_NUMBER = V_STORE_QTY.LINE_NUM
--                 AND LOT_NUMBER = V_LOT.LOT_NUMBER;
            
              IF L_REMAINING_QUANTITY = 0 THEN
                EXIT;
              END IF;
            END LOOP;
            --FOR V_LOT IN C_LOT (V_STORE_QTY.INVENTORY_ITEM_ID,
          END IF; --IF L_COUNT > 0
        
          PRINT_LOG('start inv_txn_manager_pub.process_transactions API ');
          ---  COMMIT;
          V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                                P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                                P_COMMIT           => FND_API.G_TRUE,
                                                                P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                                X_RETURN_STATUS    => L_RETURN_STATUS,
                                                                X_MSG_COUNT        => L_MSG_CNT,
                                                                X_MSG_DATA         => L_MSG_DATA,
                                                                X_TRANS_COUNT      => L_TRANS_COUNT,
                                                                P_TABLE            => 1,
                                                                P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
          PRINT_LOG('end inv_txn_manager_pub.process_transactions API ');
          PRINT_LOG('l_return_status :-  ' || L_RETURN_STATUS);
          PRINT_LOG('l_msg_cnt :-  ' || L_MSG_CNT);
        
          IF (NVL(L_RETURN_STATUS, 'E') <> 'S') THEN
            L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
          
            FOR I IN 1 .. L_MSG_CNT LOOP
              FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                              P_ENCODED       => 'F',
                              P_DATA          => L_MSG_DATA,
                              P_MSG_INDEX_OUT => X_MSG_INDEX);
              X_MSG := X_MSG || '.' || L_MSG_DATA;
            END LOOP;
            
            BEGIN
                        SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
                          INTO L_INTERFACE_ERROR
                          FROM MTL_TRANSACTIONS_INTERFACE
                         WHERE TRANSACTION_INTERFACE_ID =
                                                    L_TRANSACTION_INTERFACE_ID
                           AND SOURCE_CODE = L_TYPE;
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           L_INTERFACE_ERROR := NULL;
                     END;
          
            PRINT_LOG('Error in Subinventory Transfer:' || X_MSG ||' '||L_INTERFACE_ERROR);
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET STORE_SUBINVENTORY_TRF = 'E',
                   ERROR_MESSAGE          = SUBSTR(ERROR_MESSAGE ||
                                                   ' STORE:l_transaction_interface_id ' ||
                                                   L_TRANSACTION_INTERFACE_ID ||
                                                   L_INTERFACE_ERROR,
                                                   1,
                                                   2000)
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND NVL(QTY_RETURN_TO_STORES, 0) > 0
               AND LINE_NUM = V_STORE_QTY.LINE_NUM;
          ELSIF NVL(L_RETURN_STATUS, 'E') = 'S' THEN
            PRINT_LOG('Store Subinventory Transfer Successful');
          
            UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
               SET STORE_SUBINVENTORY_TRF = 'Y'
                  ,ERROR_MESSAGE = NULL 
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_NUMBER
               AND NVL(QTY_RETURN_TO_STORES, 0) > 0
               AND LINE_NUM = V_STORE_QTY.LINE_NUM;
          END IF; --IF (L_RETURN_STATUS <> 'S')
        END IF; --IF L_TO_SUBINVENTORY IS NOT NULL
      END LOOP; --FOR V_STORE_QTY IN C_STORE_QTY
    
      PRINT_LOG('end  store subinv loop');
      PRINT_LOG('/********************************************************************************************************/');
    END LOOP;
    ---change status of header IF line has error 
    
     UPDATE XXMSSL.XXMSSL_LRN_HEADER_T hdr 
         SET hdr.LRN_STATUS = 'APPROVE'
       WHERE hdr.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND hdr.LRN_NO = P_LRN_NUMBER
         and hdr.LRN_STATUS = 'COMPLETE'
         AND EXISTS (Select 1 from XXMSSL.XXMSSL_LRN_detail_T dtl  
         where dtl.lrn_no = hdr.lrn_no 
         and dtl.ORGANIZATION_ID = hdr.ORGANIZATION_ID
         AND ( NVL(dtl.REJECT_SUBINVENTORY_TRF,'N')  = 'E'
             OR NVL(dtl.SCRAP_SUBINVENTORY_TRF,'N')   = 'E'
             OR NVL(dtl.STORE_SUBINVENTORY_TRF,'N')   = 'E'
             OR NVL(dtl.RETURN_SUBINVENTORY_TRF,'N')  = 'E' ));
  
    FOR R_MAIL IN C_MAIL LOOP
      FND_FILE.PUT_LINE(FND_FILE.LOG, 'Calling Email Proc');
      BEGIN
        APPS.XXMSSL_LRN_PKG.P_EMAIL_NOTIF(G_USER_ID,
                                          R_MAIL.LRN_STATUS,
                                          R_MAIL.TRANSACTION_TYPE,
                                          P_LRN_NUMBER,
                                          'COMPLETE',
                                          P_ORGANIZATION_ID,
                                          NULL);
      EXCEPTION
        WHEN OTHERS THEN
          FND_FILE.PUT_LINE(FND_FILE.LOG, 'Error While Calling Email Proc');
      END;
    END LOOP;
    --C_MAIN
    --- COMMIT;
    /*************************** SUBINVENTORY TRANSFER FOR SCRAP QTY *************/
  
    --      END IF;
  EXCEPTION
    WHEN OTHERS THEN
      PRINT_LOG('EXCEPTION IN Quality SUBINVENTORY_TRANSFER:' || SQLERRM);
  END;

  PROCEDURE CHECK_APPROVE_STATUS(ITEMTYPE IN VARCHAR2,
                                 ITEMKEY  IN VARCHAR2,
                                 ACTID    IN NUMBER,
                                 FUNCMODE IN VARCHAR2,
                                 RESULT   IN OUT VARCHAR2) IS
    L_LRN_STATUS VARCHAR2(20);
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_LRN_STATUS := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                ITEMKEY  => ITEMKEY,
                                                ANAME    => 'LRN_STATUS');
    
      IF L_LRN_STATUS = 'APPROVE' THEN
        RESULT := 'COMPLETE:Y';
        RETURN;
      ELSIF L_LRN_STATUS = 'REJECT' THEN
        RESULT := 'COMPLETE:N';
        RETURN;
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG', 'CHECK_APPROVE_STATUS', SQLERRM);
      RAISE;
  END;

  PROCEDURE CHECK_COMPLETE_STATUS(ITEMTYPE IN VARCHAR2,
                                  ITEMKEY  IN VARCHAR2,
                                  ACTID    IN NUMBER,
                                  FUNCMODE IN VARCHAR2,
                                  RESULT   IN OUT VARCHAR2) IS
    L_LRN_STATUS VARCHAR2(20);
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_LRN_STATUS := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                ITEMKEY  => ITEMKEY,
                                                ANAME    => 'LRN_STATUS');
    
      IF L_LRN_STATUS = 'COMPLETE' THEN
        RESULT := 'COMPLETE:Y';
        RETURN;
      ELSIF L_LRN_STATUS <> 'COMPLETE' THEN
        RESULT := WF_ENGINE.ENG_WAITING;
        RETURN;
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG', 'CHECK_COMPLETE_STATUS', SQLERRM);
      RAISE;
  END;

  PROCEDURE GET_USER_AFTER_APPROVAL(ITEMTYPE IN VARCHAR2,
                                    ITEMKEY  IN VARCHAR2,
                                    ACTID    IN NUMBER,
                                    FUNCMODE IN VARCHAR2,
                                    RESULT   IN OUT VARCHAR2) IS
    L_ORGANIZATION_ID            NUMBER;
    L_LOOKUP_CODE                NUMBER;
    L_DESCRIPTION                VARCHAR2(4000);
    L_APPROVAL_VALUE             NUMBER;
    L_LRN_STATUS                 VARCHAR2(20);
    L_ROLE_NAME                  VARCHAR2(100) := 'APPROVER_ROLE';
    L_ROLE_DISPLAY_NAME          VARCHAR2(250) := 'LRN Approver';
    L_ROLE_USERS                 VARCHAR2(1000);
    L_PREV_ROLE                  VARCHAR2(100);
    L_PREV_ROLE_DISPLAY          VARCHAR2(250);
    L_COMPLETE_ROLE_NAME         VARCHAR2(100) := 'COMPLETE_LRN_ROLE';
    L_COMPLETE_ROLE_DISPLAY_NAME VARCHAR2(250) := 'LRN Complete';
    L_COMPLETE_ROLE_USERS        VARCHAR2(1000);
    L_COMPLETE_PREV_ROLE         VARCHAR2(100);
    L_COMPLETE_PREV_ROLE_DISPLAY VARCHAR2(250);
    L_APPROVE_COMPLETE           VARCHAR2(500);
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_ORGANIZATION_ID := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'ORGANIZATION_ID');
      L_LRN_STATUS      := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'LRN_STATUS');
    
      IF L_LRN_STATUS = 'APPROVE' THEN
        L_APPROVAL_VALUE := WF_ENGINE.GETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                                        ITEMKEY  => ITEMKEY,
                                                        ANAME    => 'AFTER_APPOVER_USER_LOOKUP');
      
        BEGIN
          SELECT RTRIM(XMLAGG(XMLELEMENT(E, DESCRIPTION || ','))
                       .EXTRACT('//text()'),
                       ',')
            INTO L_ROLE_USERS
            FROM (SELECT DESCRIPTION
                    FROM FND_LOOKUP_VALUES            FLV,
                         ORG_ORGANIZATION_DEFINITIONS OOD
                   WHERE FLV.LOOKUP_TYPE = 'XXMSSL_LRN_AFTER_APPROVAL_LIST'
                     AND FLV.TAG = OOD.ORGANIZATION_CODE
                     AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                     AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                         TRUNC(SYSDATE)
                     AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >=
                         TRUNC(SYSDATE)
                  UNION
                  SELECT USER_NAME
                    FROM XXMSSL_LRN_HEADER_T XX, FND_USER FU
                   WHERE XX.LAST_UPDATED_BY = FU.USER_ID
                     AND LRN_NO = ITEMKEY);
        EXCEPTION
          WHEN OTHERS THEN
            L_ROLE_USERS := 0;
            --                  L_DESCRIPTION := NULL;
        END;
      
        BEGIN
          SELECT NAME, DISPLAY_NAME
            INTO L_PREV_ROLE, L_PREV_ROLE_DISPLAY
            FROM WF_LOCAL_ROLES
           WHERE NAME = L_ROLE_NAME;
        
          IF L_PREV_ROLE IS NOT NULL THEN
            BEGIN
              WF_DIRECTORY.SETADHOCROLEEXPIRATION(L_ROLE_NAME, SYSDATE - 1);
              COMMIT;
              WF_DIRECTORY.SETADHOCROLESTATUS(L_ROLE_NAME, 'INACTIVE');
              COMMIT;
              WF_DIRECTORY.DELETEROLE(L_ROLE_NAME, 'WF_LOCAL_ROLES', 0);
              COMMIT;
            END;
          END IF;
        EXCEPTION
          WHEN OTHERS THEN
            L_PREV_ROLE         := NULL;
            L_PREV_ROLE_DISPLAY := NULL;
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'Inside Exception block of role remove directory' ||
                              SQLCODE || SQLERRM);
        END;
      
        BEGIN
          WF_DIRECTORY.CREATEADHOCROLE(ROLE_NAME               => L_ROLE_NAME,
                                       ROLE_DISPLAY_NAME       => L_ROLE_DISPLAY_NAME,
                                       LANGUAGE                => 'AMERICAN',
                                       TERRITORY               => 'AMERICA',
                                       ROLE_USERS              => L_ROLE_USERS,
                                       EMAIL_ADDRESS           => NULL,
                                       NOTIFICATION_PREFERENCE => 'MAILHTML',
                                       EXPIRATION_DATE         => NULL,
                                       STATUS                  => 'ACTIVE');
          COMMIT;
        END;
      
        WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'AFTER_APPOVER_USER_LOOKUP',
                                    AVALUE   => L_LOOKUP_CODE);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'AFTER_APPROVAAL_USER',
                                  AVALUE   => L_ROLE_NAME);
        COMMIT;
        RESULT := 'COMPLETE:Y';
      ELSIF L_LRN_STATUS = 'COMPLETE' THEN
        L_APPROVAL_VALUE := WF_ENGINE.GETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                                        ITEMKEY  => ITEMKEY,
                                                        ANAME    => 'COMPLETE_USER_LOOKUP');
      
        BEGIN
          /*SELECT LOOKUP_CODE, DESCRIPTION
                           INTO L_LOOKUP_CODE, L_DESCRIPTION
                           FROM (SELECT   LOOKUP_CODE, DESCRIPTION
          --                           INTO L_LOOKUP_CODE, L_DESCRIPTION
                                 FROM     FND_LOOKUP_VALUES FLV,
                                          ORG_ORGANIZATION_DEFINITIONS OOD
                                    WHERE FLV.LOOKUP_TYPE =
                                                           'XXMSSL_LRN_COMPLETION_USERS'
                                      AND FLV.TAG = OOD.ORGANIZATION_CODE
                                      AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                                      AND LOOKUP_CODE > NVL (L_APPROVAL_VALUE, 0)
                                      AND NVL (FLV.START_DATE_ACTIVE, TRUNC (SYSDATE)) <=
                                                                         TRUNC (SYSDATE)
                                      AND NVL (FLV.END_DATE_ACTIVE, TRUNC (SYSDATE)) >=
                                                                         TRUNC (SYSDATE)
                                 ORDER BY TO_NUMBER (LOOKUP_CODE))
                          WHERE ROWNUM = 1;*/
          SELECT RTRIM(XMLAGG(XMLELEMENT(E, DESCRIPTION || ','))
                       .EXTRACT('//text()'),
                       ',')
            INTO L_COMPLETE_ROLE_USERS
            FROM FND_LOOKUP_VALUES FLV, ORG_ORGANIZATION_DEFINITIONS OOD
           WHERE FLV.LOOKUP_TYPE = 'XXMSSL_LRN_COMPLETION_USERS'
             AND FLV.TAG = OOD.ORGANIZATION_CODE
             AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
             AND LOOKUP_CODE > NVL(L_APPROVAL_VALUE, 0)
             AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                 TRUNC(SYSDATE)
             AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE);
        EXCEPTION
          WHEN OTHERS THEN
            L_LOOKUP_CODE := 0;
            L_DESCRIPTION := NULL;
        END;
      
        BEGIN
          SELECT NAME, DISPLAY_NAME
            INTO L_COMPLETE_PREV_ROLE, L_COMPLETE_PREV_ROLE_DISPLAY
            FROM WF_LOCAL_ROLES
           WHERE NAME = L_COMPLETE_ROLE_NAME;
        
          IF L_COMPLETE_PREV_ROLE IS NOT NULL THEN
            BEGIN
              WF_DIRECTORY.SETADHOCROLEEXPIRATION(L_COMPLETE_ROLE_NAME,
                                                  SYSDATE - 1);
              COMMIT;
              WF_DIRECTORY.SETADHOCROLESTATUS(L_COMPLETE_ROLE_NAME,
                                              'INACTIVE');
              COMMIT;
              WF_DIRECTORY.DELETEROLE(L_COMPLETE_ROLE_NAME,
                                      'WF_LOCAL_ROLES',
                                      0);
              COMMIT;
            END;
          END IF;
        EXCEPTION
          WHEN OTHERS THEN
            L_COMPLETE_PREV_ROLE         := NULL;
            L_COMPLETE_PREV_ROLE_DISPLAY := NULL;
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'Inside Exception block of complete role remove directory' ||
                              SQLCODE || SQLERRM);
        END;
      
        BEGIN
          WF_DIRECTORY.CREATEADHOCROLE(ROLE_NAME               => L_COMPLETE_ROLE_NAME,
                                       ROLE_DISPLAY_NAME       => L_COMPLETE_ROLE_DISPLAY_NAME,
                                       LANGUAGE                => 'AMERICAN',
                                       TERRITORY               => 'AMERICA',
                                       ROLE_USERS              => L_COMPLETE_ROLE_USERS,
                                       EMAIL_ADDRESS           => NULL,
                                       NOTIFICATION_PREFERENCE => 'MAILHTML',
                                       EXPIRATION_DATE         => NULL,
                                       STATUS                  => 'ACTIVE');
          COMMIT;
        END;
      
        ----ADDE BY SHIKHA-----
        BEGIN
          FOR J IN (SELECT (SELECT (FIRST_NAME || '-' || EMPLOYEE_NUMBER)
                              FROM PER_ALL_PEOPLE_F
                             WHERE PERSON_ID IN
                                   (SELECT EMPLOYEE_ID
                                      FROM FND_USER
                                     WHERE USER_NAME = XX.DESCRIPTION)
                               AND TRUNC(SYSDATE) BETWEEN
                                   EFFECTIVE_START_DATE AND
                                   EFFECTIVE_END_DATE
                               AND CURRENT_EMPLOYEE_FLAG = 'Y') APPROVER_COMPLETION_NAME
                      FROM (SELECT DESCRIPTION
                            -- INTO L_LOOKUP_CODE, L_DESCRIPTION
                              FROM FND_LOOKUP_VALUES            FLV,
                                   ORG_ORGANIZATION_DEFINITIONS OOD
                             WHERE FLV.LOOKUP_TYPE =
                                   'XXMSSL_LRN_COMPLETION_USERS'
                               AND FLV.TAG = OOD.ORGANIZATION_CODE
                               AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                               AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                                   TRUNC(SYSDATE)
                               AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >=
                                   TRUNC(SYSDATE)
                             ORDER BY LOOKUP_CODE) XX) LOOP
            IF L_APPROVE_COMPLETE IS NULL THEN
              L_APPROVE_COMPLETE := J.APPROVER_COMPLETION_NAME;
            ELSE
              L_APPROVE_COMPLETE := L_APPROVE_COMPLETE || ' , ' ||
                                    J.APPROVER_COMPLETION_NAME;
            END IF;
          END LOOP;
        EXCEPTION
          WHEN OTHERS THEN
            L_APPROVE_COMPLETE := NULL;
        END;
      
        --ENDED BY SHIKHA---
        WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'COMPLETE_USER_LOOKUP',
                                    AVALUE   => L_LOOKUP_CODE);
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'COMPLETE_USER_NAME',
                                  AVALUE   => L_COMPLETE_ROLE_NAME);
        ----ENDED BY SHIKHA -----------
      
        -----ADDED BY SHIKHA
        WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                  ITEMKEY  => ITEMKEY,
                                  ANAME    => 'APPROVER_LIST',
                                  AVALUE   => L_APPROVE_COMPLETE);
        ------ENDED
        COMMIT;
        RESULT := 'COMPLETE:Y';
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG', 'GET_USER_AFTER_APPROVAL', SQLERRM);
      RAISE;
  END GET_USER_AFTER_APPROVAL;

  PROCEDURE CHECK_USER_APPROVAL_EXISTS(ITEMTYPE IN VARCHAR2,
                                       ITEMKEY  IN VARCHAR2,
                                       ACTID    IN NUMBER,
                                       FUNCMODE IN VARCHAR2,
                                       RESULT   IN OUT VARCHAR2) IS
    L_ORGANIZATION_ID NUMBER;
    L_LOOKUP_CODE     NUMBER;
    L_DESCRIPTION     VARCHAR2(50);
    L_APPROVAL_VALUE  NUMBER;
    L_LRN_STATUS      VARCHAR2(20);
  BEGIN
    IF FUNCMODE = 'RUN' THEN
      L_ORGANIZATION_ID := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'ORGANIZATION_ID');
      L_LRN_STATUS      := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                     ITEMKEY  => ITEMKEY,
                                                     ANAME    => 'LRN_STATUS');
    
      IF L_LRN_STATUS = 'APPROVE' THEN
        L_APPROVAL_VALUE := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                      ITEMKEY  => ITEMKEY,
                                                      ANAME    => 'AFTER_APPOVER_USER_LOOKUP');
      
        BEGIN
          SELECT LOOKUP_CODE, DESCRIPTION
            INTO L_LOOKUP_CODE, L_DESCRIPTION
            FROM (SELECT LOOKUP_CODE, DESCRIPTION
                  --                   INTO L_LOOKUP_CODE, L_DESCRIPTION
                    FROM FND_LOOKUP_VALUES            FLV,
                         ORG_ORGANIZATION_DEFINITIONS OOD
                   WHERE FLV.LOOKUP_TYPE = 'XXMSSL_LRN_AFTER_APPROVAL_LIST'
                     AND FLV.TAG = OOD.ORGANIZATION_CODE
                     AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                     AND LOOKUP_CODE > NVL(L_APPROVAL_VALUE, 0)
                     AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                         TRUNC(SYSDATE)
                     AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >=
                         TRUNC(SYSDATE)
                   ORDER BY TO_NUMBER(LOOKUP_CODE))
           WHERE ROWNUM = 1;
        EXCEPTION
          WHEN OTHERS THEN
            L_LOOKUP_CODE := 0;
            L_DESCRIPTION := NULL;
        END;
      
        IF L_LOOKUP_CODE > 0 THEN
          WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                      ITEMKEY  => ITEMKEY,
                                      ANAME    => 'AFTER_APPOVER_USER_LOOKUP',
                                      AVALUE   => L_LOOKUP_CODE);
          WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'AFTER_APPROVAAL_USER',
                                    AVALUE   => L_DESCRIPTION);
          RESULT := 'COMPLETE:Y';
        ELSIF L_LOOKUP_CODE = 0 THEN
          RESULT := 'COMPLETE:N';
        END IF;
      ELSIF L_LRN_STATUS = 'COMPLETE' THEN
        L_APPROVAL_VALUE := WF_ENGINE.GETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                                      ITEMKEY  => ITEMKEY,
                                                      ANAME    => 'COMPLETE_USER_LOOKUP');
      
        BEGIN
          SELECT LOOKUP_CODE, DESCRIPTION
            INTO L_LOOKUP_CODE, L_DESCRIPTION
            FROM (SELECT LOOKUP_CODE, DESCRIPTION
                  --                   INTO L_LOOKUP_CODE, L_DESCRIPTION
                    FROM FND_LOOKUP_VALUES            FLV,
                         ORG_ORGANIZATION_DEFINITIONS OOD
                   WHERE FLV.LOOKUP_TYPE = 'XXMSSL_LRN_COMPLETION_USERS'
                     AND FLV.TAG = OOD.ORGANIZATION_CODE
                     AND OOD.ORGANIZATION_ID = L_ORGANIZATION_ID
                     AND LOOKUP_CODE > NVL(L_APPROVAL_VALUE, 0)
                     AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <=
                         TRUNC(SYSDATE)
                     AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >=
                         TRUNC(SYSDATE)
                   ORDER BY TO_NUMBER(LOOKUP_CODE))
           WHERE ROWNUM = 1;
        EXCEPTION
          WHEN OTHERS THEN
            L_LOOKUP_CODE := 0;
            L_DESCRIPTION := NULL;
        END;
      
        IF L_LOOKUP_CODE > 0 THEN
          WF_ENGINE.SETITEMATTRNUMBER(ITEMTYPE => ITEMTYPE,
                                      ITEMKEY  => ITEMKEY,
                                      ANAME    => 'COMPLETE_USER_LOOKUP',
                                      AVALUE   => L_LOOKUP_CODE);
          WF_ENGINE.SETITEMATTRTEXT(ITEMTYPE => ITEMTYPE,
                                    ITEMKEY  => ITEMKEY,
                                    ANAME    => 'COMPLETE_USER_NAME',
                                    AVALUE   => L_DESCRIPTION);
          RESULT := 'COMPLETE:Y';
        ELSIF L_LOOKUP_CODE = 0 THEN
          RESULT := 'COMPLETE:N';
        END IF;
      END IF;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      WF_CORE.CONTEXT('XXMSSL_LRN_PKG',
                      'CHECK_USER_APPROVAL_EXISTS',
                      SQLERRM);
      RAISE;
  END CHECK_USER_APPROVAL_EXISTS;

  ---------------------------------------------------------------------------------------
  /*THIS PROCEDURE IS CREATED BY GAUTAM KUMAR . FOR LRN ERROR MESSAGE*/
  PROCEDURE XXMSSL_LRN_EXCEPTION_REP(ERRBUF  OUT VARCHAR2,
                                     RETCODE OUT NUMBER,
                                     SID_ID  NUMBER) AS
    A NUMBER;
  
    CURSOR XXMSSL_FECTH_EXCEPTION IS
      SELECT LRN_NO, ERROR_DESCRIPTION, ITEM_CODE
        FROM XXMSSL_LRN_EXCEPTION
       WHERE SIID = SID_ID;
  BEGIN
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT, 'LRN EXCEPTION ERROR DATA');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '   ');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,
                      RPAD(NVL(TO_CHAR('lrn NO'), ' '), 15) || '   ' ||
                      RPAD(NVL(TO_CHAR('Item code'), ' '), 20) || '   ' ||
                      RPAD(NVL(TO_CHAR('ERROR_DESCRIPTION'), ' '), 90));
  
    FOR I IN XXMSSL_FECTH_EXCEPTION LOOP
      FND_FILE.PUT_LINE(FND_FILE.OUTPUT,
                        RPAD(NVL(TO_CHAR(I.LRN_NO), ' '), 15) || '   ' ||
                        RPAD(NVL(TO_CHAR(I.ITEM_CODE), ' '), 20) || '   ' ||
                        RPAD(NVL(TO_CHAR(I.ERROR_DESCRIPTION), ' '), 90));
      EXIT WHEN XXMSSL_FECTH_EXCEPTION%NOTFOUND;
    END LOOP;
  
    DELETE FROM XXMSSL_LRN_EXCEPTION WHERE SIID = SID_ID;
  
    COMMIT;
  END;

  --------------------------------------------------------------------------------------
  --START ADDING BY DALJEET ON 25-NOV-2020 FOR IDACS
  PROCEDURE SUBINVENTORY_TRANSFER_MAIN(P_ORGANIZATION_ID IN NUMBER,
                                       P_LRN_NUMBER      IN VARCHAR2,
                                       P_RET_STATUS      OUT VARCHAR2,
                                       P_RET_MSG         OUT VARCHAR2) IS
    L_TRAN_TYPE VARCHAR2(50);
  BEGIN
    BEGIN
      SELECT TRANSACTION_TYPE
        INTO L_TRAN_TYPE
        FROM XXMSSL_LRN_HEADER_T
       WHERE LRN_NO = P_LRN_NUMBER
         AND ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRAN_TYPE := NULL;
    END;
  
    IF L_TRAN_TYPE = 'LRN' THEN
      SUBINVENTORY_TRANSFER(P_ORGANIZATION_ID => P_ORGANIZATION_ID,
                            P_LRN_NUMBER      => P_LRN_NUMBER,
                            P_RET_STATUS      => P_RET_STATUS,
                            P_RET_MSG         => P_RET_MSG);
    ELSIF L_TRAN_TYPE = 'MRN' THEN
      MRN_SUBINVENTORY_TRANSFER(P_ORGANIZATION_ID => P_ORGANIZATION_ID,
                                P_LRN_NUMBER      => P_LRN_NUMBER,
                                P_RET_STATUS      => P_RET_STATUS,
                                P_RET_MSG         => P_RET_MSG);
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'EXCEPTION IN SUBINVENTORY_TRANSFER_MAIN:' || SQLERRM;
      PRINT_LOG('EXCEPTION IN SUBINVENTORY_TRANSFER_MAIN:' || SQLERRM);
  END SUBINVENTORY_TRANSFER_MAIN;
  
---- package is obsolete as Procedure is no longer use V1.6--
  PROCEDURE MRN_SUBINVENTORY_TRANSFER(P_ORGANIZATION_ID IN NUMBER,
                                      P_LRN_NUMBER      IN VARCHAR2,
                                      P_RET_STATUS      OUT VARCHAR2,
                                      P_RET_MSG         OUT VARCHAR2) IS
    L_USER_ID                  NUMBER := FND_PROFILE.VALUE('USER_ID');
    L_LOGIN_ID                 NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
    L_TRANSACTION_INTERFACE_ID NUMBER;
    V_RET_VAL                  NUMBER;
    L_RETURN_STATUS            VARCHAR2(100);
    L_MSG_CNT                  NUMBER;
    L_MSG_DATA                 VARCHAR2(4000);
    L_TRANS_COUNT              NUMBER;
    X_MSG_INDEX                NUMBER;
    X_MSG                      VARCHAR2(4000);
    L_TO_SUBINVENTORY          VARCHAR2(50);
    L_COUNT                    NUMBER;
    L_TRANSACTION_TYPE_ID      NUMBER;
    L_TRANSACTION_QUANTITY     NUMBER;
    L_REMAINING_QUANTITY       NUMBER;
    LC_ORG_ID                  NUMBER := FND_PROFILE.VALUE('ORG_ID');
    L_OU                       NUMBER;
    L_RET_VAL                  NUMBER;
    L_RETURN_MSG               VARCHAR2(500);
    L_SUBINVENTORY_CNT         NUMBER := 0;
  
    CURSOR C1 IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD, XXMSSL.XXMSSL_LRN_HEADER_T XLH
       WHERE XLD.ORGANIZATION_ID = XLH.ORGANIZATION_ID
         AND XLD.LRN_NO = XLH.LRN_NO
         AND XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER
            --AND XLH.LRN_STATUS = 'APPROVE'
         AND NVL(XLD.SUBINVENTORY_TRANSFER, 'N') IN ('N', 'R')
         AND XLH.TRANSACTION_TYPE = 'MRN';
  
    CURSOR C_LOT(P_INVENTORY_ITEM_ID NUMBER,
                 P_SUBINVENTORY_CODE IN VARCHAR2) IS
      SELECT *
        FROM (SELECT MLN.LOT_NUMBER,
                     MLN.CREATION_DATE,
                     XXMSSL_LRN_PKG.GET_OHQTY(MOQ.INVENTORY_ITEM_ID,
                                              MOQ.ORGANIZATION_ID,
                                              MOQ.SUBINVENTORY_CODE,
                                              MLN.LOT_NUMBER,
                                              'ATT') TRANSACTION_QUANTITY
                FROM MTL_ONHAND_QUANTITIES MOQ, MTL_LOT_NUMBERS MLN
               WHERE MOQ.ORGANIZATION_ID = MLN.ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
                 AND MLN.LOT_NUMBER = MOQ.LOT_NUMBER
                 AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
                 AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
               GROUP BY MLN.LOT_NUMBER,
                        MOQ.INVENTORY_ITEM_ID,
                        MOQ.ORGANIZATION_ID,
                        SUBINVENTORY_CODE,
                        MLN.CREATION_DATE)
       WHERE TRANSACTION_QUANTITY > 0
       ORDER BY CREATION_DATE;
  BEGIN
    G_LRN_NO := P_LRN_NUMBER;
    G_ACTION := 'SUBINVENTORY_TRANSFER';
    PRINT_LOG('<----------- Starting MRN Subinventory Transfer Process ------------>');
    PRINT_LOG('LRN No: ' || P_LRN_NUMBER);
    PRINT_LOG('p_organization_id : ' || P_ORGANIZATION_ID);
    PRINT_LOG('Start delete from xxmssl_lrn_subinv_lot ');
  
    DELETE FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT
     WHERE LRN_NO = P_LRN_NUMBER
       AND ORGANIZATION_ID = P_ORGANIZATION_ID;
  
    PRINT_LOG('end delete from xxmssl_lrn_subinv_lot ');
    PRINT_LOG('start get transaction type');
  
    /**************** GET TRANSACTION TYPE ***************************/
    BEGIN
      SELECT TRANSACTION_TYPE_ID
        INTO L_TRANSACTION_TYPE_ID
        FROM MTL_TRANSACTION_TYPES
       WHERE TRANSACTION_TYPE_NAME = 'MRN'
         AND TRANSACTION_SOURCE_TYPE_ID = 13;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRANSACTION_TYPE_ID := NULL;
    END;
  
    PRINT_LOG('l_transaction_type_id :- ' || L_TRANSACTION_TYPE_ID);
    PRINT_LOG('end get transaction type');
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'Transaction Type ''MRN'' is not Defined';
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Transaction Type ''MRN'' is not Defined');
      RETURN;
    END IF;
  
    /**************************** CHECK PERIOD IS OPEN ****************/
    PRINT_LOG('start check period ');
  
    SELECT COUNT(*)
      INTO L_COUNT
      FROM ORG_ACCT_PERIODS_V
     WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
       AND TRUNC(SYSDATE) BETWEEN START_DATE AND END_DATE
       AND UPPER(STATUS) = 'OPEN';
  
    IF L_COUNT = 0 THEN
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'Period is Not Open';
      PRINT_LOG('Period is Not Open');
      RETURN;
    END IF;
  
    PRINT_LOG('end check period ');
  
    BEGIN
      SELECT OPERATING_UNIT
        INTO L_OU
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_OU := NULL;
    END;
  
    PRINT_LOG('l_ou :- ' || L_OU);
    MO_GLOBAL.SET_POLICY_CONTEXT('S', L_OU);
    INV_GLOBALS.SET_ORG_ID(P_ORGANIZATION_ID);
    MO_GLOBAL.INIT('INV');
  
    L_SUBINVENTORY_CNT := 0;
  
    /********************* TO SUBINVENTORY *******************/
    BEGIN
      L_TO_SUBINVENTORY := FND_PROFILE.VALUE('XXMSSL_MRN_LOCATION');
    
      /* SELECT MSI.SECONDARY_INVENTORY_NAME  ---VIKAS
        INTO L_TO_SUBINVENTORY
        FROM FND_LOOKUP_VALUES FLV,
             ORG_ORGANIZATION_DEFINITIONS OOD,
             MTL_SECONDARY_INVENTORIES MSI
       WHERE LOOKUP_TYPE = 'XXMSSL_LRN_MRB_SUBINVENTORY'
         AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
         AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
         AND FLV.ENABLED_FLAG = 'Y'
         AND NVL (FLV.START_DATE_ACTIVE, TRUNC (SYSDATE)) <=
                                                            TRUNC (SYSDATE)
         AND NVL (FLV.END_DATE_ACTIVE, TRUNC (SYSDATE)) >= TRUNC (SYSDATE)
         AND ROWNUM = 1;
         EXCEPTION
      WHEN OTHERS
      THEN
         L_TO_SUBINVENTORY := NULL;
         P_RET_STATUS := 'E';
         P_RET_MSG :=
            'ERROR : NO SUBINVENTORY DEFINED IN LOOKUP ''XXMSSL_LRN_MRB_SUBINVENTORY'' FOR SUBINVENTORY TRANSFER';
         PRINT_LOG
            ('ERROR : NO SUBINVENTORY DEFINED IN LOOKUP ''XXMSSL_LRN_MRB_SUBINVENTORY'' FOR SUBINVENTORY TRANSFER'
            );
         RETURN;*/
    END;
  
    BEGIN
      SELECT COUNT(1)
        INTO L_SUBINVENTORY_CNT
        FROM MTL_SECONDARY_INVENTORIES MSI
       WHERE -1 = -1
         AND UPPER(MSI.SECONDARY_INVENTORY_NAME) = UPPER(L_TO_SUBINVENTORY)
         AND MSI.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND NVL(MSI.DISABLE_DATE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE);
    EXCEPTION
      WHEN OTHERS THEN
        L_SUBINVENTORY_CNT := NULL;
    END;
  
    IF L_SUBINVENTORY_CNT = 0 THEN
    
      PRINT_LOG('Error:From Sub-inventory Does Not Exist In System:-  ' ||
                L_TO_SUBINVENTORY);
      RETURN;
    END IF;
  
    PRINT_LOG('l_to_subinventory :- ' || L_TO_SUBINVENTORY);
    PRINT_LOG('Strat Loop C1 :- ');
  
    FOR V1 IN C1 LOOP
      PRINT_LOG('inventory_item_id :- ' || V1.INVENTORY_ITEM_ID);
      PRINT_LOG('subinventory_code :- ' || V1.SUBINVENTORY_CODE);
      PRINT_LOG('lrn_quantity :- ' || V1.LRN_QUANTITY);
      L_RETURN_STATUS := NULL;
      L_MSG_CNT       := NULL;
      L_MSG_DATA      := NULL;
      L_TRANS_COUNT   := NULL;
    
      SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
        INTO L_TRANSACTION_INTERFACE_ID
        FROM DUAL;
    
      PRINT_LOG(' start insert into mtl_transactions_interface');
    
      INSERT INTO MTL_TRANSACTIONS_INTERFACE
        (CREATED_BY,
         CREATION_DATE,
         INVENTORY_ITEM_ID,
         LAST_UPDATED_BY,
         LAST_UPDATE_DATE,
         LAST_UPDATE_LOGIN,
         LOCK_FLAG,
         ORGANIZATION_ID,
         PROCESS_FLAG,
         SOURCE_CODE,
         SOURCE_HEADER_ID,
         SOURCE_LINE_ID,
         SUBINVENTORY_CODE,
         TRANSACTION_DATE,
         TRANSACTION_HEADER_ID,
         TRANSACTION_INTERFACE_ID,
         TRANSACTION_MODE,
         TRANSACTION_QUANTITY,
         TRANSACTION_TYPE_ID,
         TRANSACTION_UOM,
         TRANSFER_SUBINVENTORY,
         TRANSACTION_REFERENCE)
      VALUES
        (L_USER_ID,
         SYSDATE,
         V1.INVENTORY_ITEM_ID,
         L_USER_ID,
         SYSDATE,
         L_LOGIN_ID,
         2,
         P_ORGANIZATION_ID,
         1,
         'MRN',
         1,
         2,
         V1.SUBINVENTORY_CODE,
         SYSDATE,
         L_TRANSACTION_INTERFACE_ID,
         L_TRANSACTION_INTERFACE_ID,
         3,
         V1.LRN_QUANTITY,
         L_TRANSACTION_TYPE_ID,
         V1.UOM,
         L_TO_SUBINVENTORY,
         P_LRN_NUMBER);
    
      /*FOR LOG PURPOSE */
      INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
        (CREATED_BY,
         CREATION_DATE,
         INVENTORY_ITEM_ID,
         LAST_UPDATED_BY,
         LAST_UPDATE_DATE,
         LAST_UPDATE_LOGIN,
         LOCK_FLAG,
         ORGANIZATION_ID,
         PROCESS_FLAG,
         SOURCE_CODE,
         SOURCE_HEADER_ID,
         SOURCE_LINE_ID,
         SUBINVENTORY_CODE,
         TRANSACTION_DATE,
         TRANSACTION_HEADER_ID,
         TRANSACTION_INTERFACE_ID,
         TRANSACTION_MODE,
         TRANSACTION_QUANTITY,
         TRANSACTION_TYPE_ID,
         TRANSACTION_UOM,
         TRANSFER_SUBINVENTORY,
         TRANSACTION_REFERENCE)
      VALUES
        (L_USER_ID,
         SYSDATE,
         V1.INVENTORY_ITEM_ID,
         L_USER_ID,
         SYSDATE,
         L_LOGIN_ID,
         2,
         P_ORGANIZATION_ID,
         1,
         'MRN',
         1,
         2,
         V1.SUBINVENTORY_CODE,
         SYSDATE,
         L_TRANSACTION_INTERFACE_ID,
         L_TRANSACTION_INTERFACE_ID,
         3,
         V1.LRN_QUANTITY,
         L_TRANSACTION_TYPE_ID,
         V1.UOM,
         L_TO_SUBINVENTORY,
         P_LRN_NUMBER);
    
      PRINT_LOG(' end  insert into mtl_transactions_interface');
    
      /***************** CHECK ITEM IS LOT CONTROLLED ***************/
      SELECT COUNT(*)
        INTO L_COUNT
        FROM MTL_SYSTEM_ITEMS_B
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND INVENTORY_ITEM_ID = V1.INVENTORY_ITEM_ID
         AND LOT_CONTROL_CODE = 2;
    
      PRINT_LOG(' check item is lot control l_count = ' || L_COUNT);
    
      IF L_COUNT > 0 THEN
        L_REMAINING_QUANTITY := V1.LRN_QUANTITY;
        PRINT_LOG(' insert into lot loop l_remaining_quantity=  ' ||
                  L_REMAINING_QUANTITY);
      
        FOR V_LOT IN C_LOT(V1.INVENTORY_ITEM_ID, V1.SUBINVENTORY_CODE) LOOP
          L_TRANSACTION_QUANTITY := NULL;
          PRINT_LOG(' lot_quantity =  ' || V_LOT.TRANSACTION_QUANTITY);
          PRINT_LOG(' Lot no.  =  ' || V_LOT.LOT_NUMBER);
        
          IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
            L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
            L_REMAINING_QUANTITY   := 0;
          ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
            L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
            L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                      V_LOT.TRANSACTION_QUANTITY;
          END IF;
        
          PRINT_LOG(' l_remaining_quantity =  ' || L_REMAINING_QUANTITY);
          PRINT_LOG(' l_transaction_quantity  ' || L_TRANSACTION_QUANTITY);
          PRINT_LOG(' Insert into mtl_transaction_lots_interface  ');
        
          INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
            (TRANSACTION_INTERFACE_ID,
             LOT_NUMBER,
             TRANSACTION_QUANTITY,
             LAST_UPDATE_DATE,
             LAST_UPDATED_BY,
             CREATION_DATE,
             CREATED_BY)
          VALUES
            (L_TRANSACTION_INTERFACE_ID,
             V_LOT.LOT_NUMBER,
             L_TRANSACTION_QUANTITY,
             SYSDATE,
             L_USER_ID,
             SYSDATE,
             L_USER_ID);
        
          PRINT_LOG(' Insert into xxmssl_lrn_subinv_lot  ');
        
          INSERT INTO XXMSSL.XXMSSL_LRN_SUBINV_LOT
            (ORGANIZATION_ID,
             LRN_NO,
             INVENTORY_ITEM_ID,
             SUBINVENTORY_CODE,
             LOT_NUMBER,
             LOT_QUANTITY,
             CREATION_DATE,
             CREATED_BY,
             LINE_NUMBER)
          VALUES
            (P_ORGANIZATION_ID,
             P_LRN_NUMBER,
             V1.INVENTORY_ITEM_ID,
             L_TO_SUBINVENTORY,
             V_LOT.LOT_NUMBER,
             L_TRANSACTION_QUANTITY,
             SYSDATE,
             L_USER_ID,
             V1.LINE_NUM);
        
          IF L_REMAINING_QUANTITY = 0 THEN
            EXIT;
          END IF;
        END LOOP;
      END IF;
    
      PRINT_LOG(' start inv_txn_manager_pub.process_transactions  API ');
      --   COMMIT;
      V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                            P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                            P_COMMIT           => FND_API.G_TRUE,
                                                            P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                            X_RETURN_STATUS    => L_RETURN_STATUS,
                                                            X_MSG_COUNT        => L_MSG_CNT,
                                                            X_MSG_DATA         => L_MSG_DATA,
                                                            X_TRANS_COUNT      => L_TRANS_COUNT,
                                                            P_TABLE            => 1,
                                                            P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
      PRINT_LOG(' end inv_txn_manager_pub.process_transactions  API ');
      PRINT_LOG(' return status :- ' || NVL(L_RETURN_STATUS, 'E'));
      PRINT_LOG(' l_msg_cnt :- ' || NVL(L_MSG_CNT, 0));
    
      IF (NVL(L_RETURN_STATUS, 'E') <> 'S') THEN
        L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
      
        FOR I IN 1 .. L_MSG_CNT LOOP
          FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                          P_ENCODED       => 'F',
                          P_DATA          => L_MSG_DATA,
                          P_MSG_INDEX_OUT => X_MSG_INDEX);
          X_MSG := X_MSG || '.' || L_MSG_DATA;
        END LOOP;
      
        PRINT_LOG('Error in Subinventory Transfer:' || X_MSG);
        P_RET_STATUS := 'E';
        P_RET_MSG    := X_MSG;
      
        UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
           SET SUBINVENTORY_TRANSFER = 'E',
               ERROR_MESSAGE         = SUBSTR(ERROR_MESSAGE ||
                                              ' SUBMIT:l_transaction_interface_id ' ||
                                              L_TRANSACTION_INTERFACE_ID ||
                                              P_RET_MSG,
                                              1,
                                              2000)
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND LRN_NO = P_LRN_NUMBER
           AND LINE_NUM = V1.LINE_NUM;
      ELSIF NVL(L_RETURN_STATUS, 'E') = 'S' THEN
        P_RET_STATUS := 'S';
        P_RET_MSG    := NULL;
        PRINT_LOG('Subinventory Transfer Successful');
      
        UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
           SET SUBINVENTORY_TRANSFER = 'Y'
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND LRN_NO = P_LRN_NUMBER
           AND LINE_NUM = V1.LINE_NUM;
      
        INSERT_MRN_BALANCE(P_ORGANIZATION_ID => P_ORGANIZATION_ID,
                           P_LRN_NUMBER      => P_LRN_NUMBER,
                           P_LINE_NUMBER     => V1.LINE_NUM,
                           P_RET_STATUS      => L_RET_VAL,
                           P_RET_MSG         => L_RETURN_MSG);
      END IF;
    END LOOP;
  
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'EXCEPTION IN MRN_SUBINVENTORY_TRANSFER:' || SQLERRM;
      PRINT_LOG('EXCEPTION IN MRN_SUBINVENTORY_TRANSFER:' || SQLERRM);
  END MRN_SUBINVENTORY_TRANSFER;

  PROCEDURE INSERT_MRN_BALANCE(P_ORGANIZATION_ID IN NUMBER,
                               P_LRN_NUMBER      IN VARCHAR2,
                               P_LINE_NUMBER     IN NUMBER,
                               P_RET_STATUS      OUT VARCHAR2,
                               P_RET_MSG         OUT VARCHAR2) IS
    L_ORG_CODE  VARCHAR2(10);
    L_ITEM_CODE VARCHAR2(50);
    L_QTY       NUMBER;
    L_CNT       NUMBER := 0;
  BEGIN
    BEGIN
      SELECT ORGANIZATION_CODE
        INTO L_ORG_CODE
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_ORG_CODE := NULL;
    END;
  
    BEGIN
      SELECT ITEM_CODE, LRN_QUANTITY
        INTO L_ITEM_CODE, L_QTY
        FROM XXMSSL_LRN_DETAIL_T
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND LRN_NO = P_LRN_NUMBER
         AND LINE_NUM = P_LINE_NUMBER
         AND SUBINVENTORY_TRANSFER = 'Y';
    EXCEPTION
      WHEN OTHERS THEN
        L_ITEM_CODE := NULL;
        L_QTY       := NULL;
    END;
  
    SELECT COUNT(1)
      INTO L_CNT
      FROM XXIDACS.XXMSSL_MRN_REISSUE
     WHERE IO_CODE = L_ORG_CODE
       AND ITEM_CODE = L_ITEM_CODE;
  
    IF L_CNT = 0 THEN
      INSERT INTO XXIDACS.XXMSSL_MRN_REISSUE
        (IO_CODE, ITEM_CODE, MRN_QTY, MRN_BALANCE_QTY)
      VALUES
        (L_ORG_CODE, L_ITEM_CODE, L_QTY, L_QTY);
    ELSE
      UPDATE XXIDACS.XXMSSL_MRN_REISSUE
         SET MRN_QTY         = MRN_QTY + L_QTY,
             MRN_BALANCE_QTY = MRN_BALANCE_QTY + L_QTY
       WHERE IO_CODE = L_ORG_CODE
         AND ITEM_CODE = L_ITEM_CODE;
    END IF;
  
    PRINT_LOG('MRN Balance IO:' || L_ORG_CODE || ' Item:' || L_ITEM_CODE ||
              ' Successfully added');
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      PRINT_LOG('Error insert_mrn_balance:' || SQLERRM);
      P_RET_STATUS := 'E';
      P_RET_MSG    := 'Error insert_mrn_balance:' || SQLERRM;
  END INSERT_MRN_BALANCE;

  --END OF ADDING BY DALJEET ON 25-NOV-2020 FOR IDACS
  ------------------------------------------------------------------------
  /**********************************************************************************************************
  REM COPYRIGHT (C) 2025 MOTHERSON ALL RIGHTS RESERVED.
  REM *******************************************************************************************************
  REM FILE NAME                : XXMSSL_LRN_PKG.P_GENERATE_OUTPUT
  REM DOC REF(S)               : REFER OLD PACKAGE XXMSSL_LRN_PKG
  REM PROJECT                  : MOTHERSON PROJECT
  REM DESCRIPTION              : FOR VIEW THE PROCESS RECORD OUTPUT, AUTHOR: RAVISH CHAUHAN
  REM
  REM CHANGE HISTORY INFORMATION
  REM --------------------------
  REM VERSION  DATE         AUTHOR           CHANGE REFERENCE / DESCRIPTION
  REM -------  -----------  ---------------  ----------------------------------------
  REM 1.0     07-JAN-2025     VIKAS CHAUHAN   INITIAL VERSION
  REM *******************************************************************************************************/
  PROCEDURE P_GENERATE_OUTPUT(P_LRN_MRN_NUM     VARCHAR2,
                              P_LRN_MRN_STATUS  VARCHAR2,
                              P_LRN_MRN_TYPE    VARCHAR2,
                              P_ORGANIZATION_ID NUMBER,
                              P_ORGANIZATION    VARCHAR2,
                              P_TO_SUBINV       VARCHAR2,
                              P_REQUEST_ID      NUMBER) IS
    L_PICKED_RECORDS        NUMBER;
    L_VALIDATED_RECORDS     NUMBER;
    L_PROCESSED_RECORDS     NUMBER;
    L_FAILED_RECORDS        NUMBER;
    L_OVE_RECORDS           NUMBER;
    L_ASSIGN_FAILED_RECORDS NUMBER;
    L_TYPE                  VARCHAR2(30);
  
    CURSOR C_RECORDS IS
      SELECT LRN_NO,
             LINE_NUM,
             ORGANIZATION_ID,
             ITEM_CODE,
             INVENTORY_ITEM_ID,
             ITEM_DESCRIPTION,
             SUBINVENTORY_CODE,
             SUBINVENTORY_QTY,
             LRN_QUANTITY,
             SUBINVENTORY_TRANSFER,
             ERROR_MESSAGE
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T
       WHERE -1 = -1
         AND ORGANIZATION_ID = P_ORGANIZATION_ID
         AND LRN_NO = P_LRN_MRN_NUM
         AND ERROR_MESSAGE IS NOT NULL
         AND REQUEST_ID = P_REQUEST_ID
       ORDER BY LINE_NUM;
  
    CURSOR C_SUCCESS_RECORDS IS
      SELECT LRN_NO,
             LINE_NUM,
             ORGANIZATION_ID,
             ITEM_CODE,
             INVENTORY_ITEM_ID,
             ITEM_DESCRIPTION,
             SUBINVENTORY_CODE,
             SUBINVENTORY_QTY,
             LRN_QUANTITY,
             SUBINVENTORY_TRANSFER,
             ERROR_MESSAGE
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T
       WHERE -1 = -1
         AND ORGANIZATION_ID = P_ORGANIZATION_ID
         AND LRN_NO = P_LRN_MRN_NUM
         AND ERROR_MESSAGE IS NULL
         AND REQUEST_ID = P_REQUEST_ID
       ORDER BY LINE_NUM;
  BEGIN
    SELECT COUNT(*)
      INTO L_PICKED_RECORDS
      FROM XXMSSL.XXMSSL_LRN_DETAIL_T
     WHERE -1 = -1
       AND ORGANIZATION_ID = P_ORGANIZATION_ID
       AND LRN_NO = P_LRN_MRN_NUM
       AND REQUEST_ID = P_REQUEST_ID;
  
    SELECT COUNT(*)
      INTO L_PROCESSED_RECORDS
      FROM XXMSSL.XXMSSL_LRN_DETAIL_T
     WHERE -1 = -1
       AND ORGANIZATION_ID = P_ORGANIZATION_ID
       AND LRN_NO = P_LRN_MRN_NUM
       AND ERROR_MESSAGE IS NULL
       AND REQUEST_ID = P_REQUEST_ID;
  
    SELECT COUNT(*)
      INTO L_FAILED_RECORDS
      FROM XXMSSL.XXMSSL_LRN_DETAIL_T
     WHERE -1 = -1
       AND ORGANIZATION_ID = P_ORGANIZATION_ID
       AND LRN_NO = P_LRN_MRN_NUM
       AND ERROR_MESSAGE IS NOT NULL
       AND REQUEST_ID = P_REQUEST_ID;
  
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('-', 100, '-'));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT,
                           'Program Request ID: ' || P_REQUEST_ID ||
                           ' User ID: ' || G_USER_ID || ' Run Date: ' ||
                           TO_CHAR(SYSDATE, 'DD-MON-YYYY'));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('-', 100, '-'));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('*', 100, '*'));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT,
                           'Total Records Picked: ' || L_PICKED_RECORDS);
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT,
                           'Total Records Processed: ' ||
                           L_PROCESSED_RECORDS);
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT,
                           'Total Records Failed(E): ' || L_FAILED_RECORDS);
    BEGIN
      SELECT DECODE(P_LRN_MRN_TYPE,
                    'R',
                    'REJECT',
                    'C',
                    'RETURN TO CREATOR',
                    P_LRN_MRN_TYPE)
        INTO L_TYPE
        FROM DUAL;
    EXCEPTION
      WHEN OTHERS THEN
        L_TYPE := NULL;
    END;
  
    IF L_PROCESSED_RECORDS > 0 THEN
      APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
      FND_FILE.PUT_LINE(2,
                        'Following Are The Processed Records Details For Transaction Type: ' ||
                        L_TYPE || ' (' || P_LRN_MRN_TYPE || ')' || ' No: ' ||
                        P_LRN_MRN_NUM);
    
      BEGIN
        APPS.XXMSSL_LRN_PKG.P_EMAIL_NOTIF(G_USER_ID,
                                          P_LRN_MRN_STATUS,
                                          'LRN',
                                          P_LRN_MRN_NUM,
                                          L_TYPE,
                                          P_ORGANIZATION_ID,
                                          NULL);
      EXCEPTION
        WHEN OTHERS THEN
          FND_FILE.PUT_LINE(FND_FILE.LOG, 'Error While Calling Email Proc');
      END;
      APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
      FND_FILE.PUT_LINE(2,
                        'LINE_NUM' || CHR(9) || 'ORGANIZATION' || CHR(9) ||
                        'ITEM_CODE' || CHR(9) || 'SUBINVENTORY_CODE' ||
                        CHR(9) || 'SUBINVENTORY_QTY' || CHR(9) ||
                        'TO_SUBINVENTORY_CODE' || CHR(9) || 'LRN_QUANTITY' ||
                        CHR(9) || 'ERROR_MESSAGE');
      APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('-', 100, '-'));
    
      FOR R_SUCCESS_RECORDS IN C_SUCCESS_RECORDS LOOP
        FND_FILE.PUT_LINE(2,
                          R_SUCCESS_RECORDS.LINE_NUM || CHR(9) ||
                          P_ORGANIZATION || CHR(9) ||
                          R_SUCCESS_RECORDS.ITEM_CODE || CHR(9) ||
                          R_SUCCESS_RECORDS.SUBINVENTORY_CODE || CHR(9) ||
                          R_SUCCESS_RECORDS.SUBINVENTORY_QTY || CHR(9) ||
                          P_TO_SUBINV || CHR(9) ||
                          R_SUCCESS_RECORDS.LRN_QUANTITY || CHR(9) ||
                          R_SUCCESS_RECORDS.ERROR_MESSAGE);
      END LOOP;
    END IF;
  
    IF L_FAILED_RECORDS > 0 THEN
      APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
      FND_FILE.PUT_LINE(2,
                        'Following Are The Error Records Details For Transaction Type: ' ||
                        L_TYPE || ' (' || P_LRN_MRN_TYPE || ')' || ' No: ' ||
                        P_LRN_MRN_NUM);
      APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
      FND_FILE.PUT_LINE(2,
                        'LINE_NUM' || CHR(9) || 'ORGANIZATION' || CHR(9) ||
                        'ITEM_CODE' || CHR(9) || 'SUBINVENTORY_CODE' ||
                        CHR(9) || 'SUBINVENTORY_QTY' || CHR(9) ||
                        'TO_SUBINVENTORY_CODE' || CHR(9) || 'LRN_QUANTITY' ||
                        CHR(9) || 'ERROR_MESSAGE');
      APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('-', 100, '-'));
    
      FOR R_RECORDS IN C_RECORDS LOOP
        FND_FILE.PUT_LINE(2,
                          R_RECORDS.LINE_NUM || CHR(9) || P_ORGANIZATION ||
                          CHR(9) || R_RECORDS.ITEM_CODE || CHR(9) ||
                          R_RECORDS.SUBINVENTORY_CODE || CHR(9) ||
                          R_RECORDS.SUBINVENTORY_QTY || CHR(9) ||
                          P_TO_SUBINV || CHR(9) || R_RECORDS.LRN_QUANTITY ||
                          CHR(9) || R_RECORDS.ERROR_MESSAGE);
        APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('-', 100, '-'));
      END LOOP;
    END IF;
  
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('*', 100, '*'));
  END P_GENERATE_OUTPUT;
  /**********************************************************************************************************
  REM COPYRIGHT (C) 2025 MOTHERSON ALL RIGHTS RESERVED.
  REM *******************************************************************************************************
  REM FILE NAME                : XXMSSL_LRN_PKG.P_PRAGMA_RECORDS
  REM DOC REF(S)               : REFER OLD PACKAGE XXMSSL_LRN_PKG
  REM PROJECT                  : MOTHERSON PROJECT
  REM DESCRIPTION              : CAPTURE THE ERROR LOG IN STATING TABLE, AUTHOR: RAVISH CHAUHAN
  REM
  REM CHANGE HISTORY INFORMATION
  REM --------------------------
  REM VERSION  DATE         AUTHOR           CHANGE REFERENCE / DESCRIPTION
  REM -------  -----------  ---------------  ----------------------------------------
  REM 1.0     07-JAN-2025     VIKAS CHAUHAN   INITIAL VERSION
  REM *******************************************************************************************************/
  PROCEDURE P_PRAGMA_RECORDS(P_MODE            VARCHAR2,
                             P_LRN_MRN_STATUS  VARCHAR2,
                             P_LRN_MRN_TYPE    VARCHAR2,
                             P_LRN_MRN_NUM     VARCHAR2,
                             P_ORGANIZATION_ID NUMBER,
                             P_LINE_NUM        NUMBER,
                             P_ITEM_ID         NUMBER,
                             P_ERROR_MSG       VARCHAR2,
                             P_REQUEST_ID      NUMBER) IS
    --PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    IF P_MODE = 'HEADER' THEN
      BEGIN
        UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
           SET ERROR_MESSAGE = P_ERROR_MSG, REQUEST_ID = P_REQUEST_ID
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND LRN_NO = P_LRN_MRN_NUM;
      EXCEPTION
        WHEN OTHERS THEN
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'Error In Procedure P_Pragma_Records: Block P_MODE: ' ||
                            P_MODE ||
                            '  While Update the API Error Message In Staging 
                         table xxmssl_lrn_detail_t for LRN/MRN No.: ' ||
                            P_LRN_MRN_NUM || ' and  Line Num: ' ||
                            P_LINE_NUM || SQLERRM);
      END;
    END IF;
  
    IF P_MODE = 'LINE' THEN
      BEGIN
        UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
           SET ERROR_MESSAGE         = P_ERROR_MSG,
               REQUEST_ID            = P_REQUEST_ID,
               SUBINVENTORY_TRANSFER = 'E'
         WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
           AND LRN_NO = P_LRN_MRN_NUM
           AND LINE_NUM = P_LINE_NUM;
      EXCEPTION
        WHEN OTHERS THEN
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'Error In Procedure P_Pragma_Records: Block P_MODE: ' ||
                            P_MODE ||
                            '  While Update the API Error Message In Staging 
                         table xxmssl_lrn_detail_t for LRN/MRN No.: ' ||
                            P_LRN_MRN_NUM || ' and  Line Num: ' ||
                            P_LINE_NUM || SQLERRM);
      END;
    END IF;
  
    BEGIN
      UPDATE XXMSSL.XXMSSL_LRN_HEADER_T
         SET LRN_STATUS = P_LRN_MRN_STATUS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
         AND LRN_NO = P_LRN_MRN_NUM;
    EXCEPTION
      WHEN OTHERS THEN
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Error In Procedure P_Pragma_Records: Block P_MODE: ' ||
                          P_MODE ||
                          '  While Update the API Error Message In Staging 
                         table XXMSSL_LRN_HEADER_T for LRN/MRN No.: ' ||
                          P_LRN_MRN_NUM || ' and  Line Num: ' || P_LINE_NUM ||
                          SQLERRM);
    END;
  
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      PRINT_LOG('error in p_pragma_records ' || SQLERRM);
  END P_PRAGMA_RECORDS;

  /**********************************************************************************************************
  REM COPYRIGHT (C) 2025 MOTHERSON ALL RIGHTS RESERVED.
  REM *******************************************************************************************************
  REM FILE NAME                : XXMSSL_LRN_PKG.LRN_SUBINVENTORY_TRANSFER
  REM DOC REF(S)               : REFER OLD PACKAGE XXMSSL_LRN_PKG
  REM PROJECT                  : MOTHERSON PROJECT
  REM DESCRIPTION              :XXMSSL: LRN-MRN SUB INVENTORY TRANSFER PROGRAM CEMLI-C062, AUTHOR: RAVISH CHAUHAN
  REM
  REM CHANGE HISTORY INFORMATION
  REM --------------------------
  REM VERSION  DATE         AUTHOR           CHANGE REFERENCE / DESCRIPTION
  REM -------  -----------  ---------------  ----------------------------------------
  REM 1.0     07-JAN-2025     VIKAS CHAUHAN   INITIAL VERSION
  REM *******************************************************************************************************/
  PROCEDURE LRN_SUBINVENTORY_TRANSFER(ERRBUF            OUT VARCHAR2,
                                      RETCODE           OUT VARCHAR2,
                                      P_LRN_MRN_STATUS  VARCHAR2,
                                      P_LRN_MRN_TYPE    VARCHAR2,
                                      P_LRN_MRN_NUM     VARCHAR2,
                                      P_ORGANIZATION_ID NUMBER) IS
    L_USER_ID                  NUMBER := FND_PROFILE.VALUE('USER_ID');
    L_LOGIN_ID                 NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
    L_TRANSACTION_INTERFACE_ID NUMBER;
    V_RET_VAL                  NUMBER;
    L_RETURN_STATUS            VARCHAR2(100);
    L_MSG_CNT                  NUMBER;
    L_MSG_DATA                 VARCHAR2(4000);
    L_TRANS_COUNT              NUMBER;
    X_MSG_INDEX                NUMBER;
    X_MSG                      VARCHAR2(4000);
    L_TO_SUBINVENTORY          VARCHAR2(50);
    L_COUNT                    NUMBER;
    L_TRANSACTION_TYPE_ID      NUMBER;
    L_TRANSACTION_QUANTITY     NUMBER;
    L_REMAINING_QUANTITY       NUMBER;
    LC_ORG_ID                  NUMBER := FND_PROFILE.VALUE('ORG_ID');
    L_OU                       NUMBER;
    L_ONHAND_QTY               NUMBER;
    L_ERROR_MESSAGE            VARCHAR2(4000);
    L_HEADER_FLAG              VARCHAR2(1);
    L_PROFILE_SUBINVENTORY     VARCHAR2(50);
    L_INTERFACE_ERROR          VARCHAR2(4000);
    L_ORGANIZATION_NAME        VARCHAR2(240);
    L_RET_VAL                  NUMBER;
    L_RETURN_MSG               VARCHAR2(2000);
  
    CURSOR C_MAIN_CUR IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD, XXMSSL.XXMSSL_LRN_HEADER_T XLH
       WHERE XLD.ORGANIZATION_ID = XLH.ORGANIZATION_ID
         AND XLD.LRN_NO = XLH.LRN_NO
         AND XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_MRN_NUM
         AND NVL(XLD.SUBINVENTORY_TRANSFER, 'N') IN ('N', 'R', 'E')
         AND XLH.TRANSACTION_TYPE = P_LRN_MRN_TYPE; --'LRN';
  
    CURSOR C_LOT(P_INVENTORY_ITEM_ID NUMBER,
                 P_SUBINVENTORY_CODE IN VARCHAR2) IS
      SELECT *
        FROM (SELECT MLN.LOT_NUMBER,
                     MLN.CREATION_DATE,
                     XXMSSL_LRN_PKG.GET_OHQTY(MOQ.INVENTORY_ITEM_ID,
                                              MOQ.ORGANIZATION_ID,
                                              MOQ.SUBINVENTORY_CODE,
                                              MLN.LOT_NUMBER,
                                              'ATT') TRANSACTION_QUANTITY
                FROM MTL_ONHAND_QUANTITIES MOQ, MTL_LOT_NUMBERS MLN
               WHERE MOQ.ORGANIZATION_ID = MLN.ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
                 AND MLN.LOT_NUMBER = MOQ.LOT_NUMBER
                 AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
                 AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
               GROUP BY MLN.LOT_NUMBER,
                        MOQ.INVENTORY_ITEM_ID,
                        MOQ.ORGANIZATION_ID,
                        SUBINVENTORY_CODE,
                        MLN.CREATION_DATE)
       WHERE TRANSACTION_QUANTITY > 0
       ORDER BY CREATION_DATE;
  BEGIN
    G_LRN_NO := P_LRN_MRN_NUM;
    --G_ACTION := 'SUBINVENTORY_TRANSFER';
    L_HEADER_FLAG          := 'S';
    L_PROFILE_SUBINVENTORY := NULL;
    L_ERROR_MESSAGE        := NULL;
    L_INTERFACE_ERROR      := NULL;
    L_TRANSACTION_TYPE_ID  := NULL;
    L_COUNT                := 0;
    L_PROFILE_SUBINVENTORY := NULL;
    L_TO_SUBINVENTORY      := NULL;
    L_ORGANIZATION_NAME    := NULL;
    G_REQUEST_ID           := FND_GLOBAL.CONC_REQUEST_ID;
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('*', 100, '*'));
    FND_FILE.PUT_LINE(2,
                      'Start ' || P_LRN_MRN_TYPE ||
                      ' Subinventory Transfer Process');
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('*', 100, '*'));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
    PRINT_LOG(RPAD('*', 100, '*'));
    FND_FILE.PUT_LINE(1,
                      'Start ' || P_LRN_MRN_TYPE ||
                      ' Subinventory Transfer Process');
    PRINT_LOG(RPAD('*', 100, '*'));
    PRINT_LOG(RPAD(' ', 100, ' '));
    PRINT_LOG('Program Request ID: ' || G_REQUEST_ID);
    PRINT_LOG('Transaction Type: ' || P_LRN_MRN_TYPE || ' Number: ' ||
              P_LRN_MRN_NUM);
    PRINT_LOG('Transaction Type: ' || P_LRN_MRN_TYPE);
    PRINT_LOG('Current Status: ' || P_LRN_MRN_STATUS);
    PRINT_LOG('Organization ID: ' || P_ORGANIZATION_ID);
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      'Data Delete Process Start from XXMSSL_LRN_SUBINV_LOT. ');
  
    --   -- v1.5 remove custom lot process
    --   BEGIN
    --         DELETE FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT
    --               WHERE LRN_NO = P_LRN_MRN_NUM
    --                 AND ORGANIZATION_ID = P_ORGANIZATION_ID;
    --      EXCEPTION
    --         WHEN OTHERS
    --         THEN
    --            FND_FILE.PUT_LINE
    --                     (FND_FILE.LOG,
    --                      'Error: While Data Delete from XXMSSL_LRN_SUBINV_LOT. '
    --                     );
    --      END;
  
    BEGIN
      UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
         SET ERROR_MESSAGE = NULL
       WHERE LRN_NO = P_LRN_MRN_NUM
         AND ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Error: While Data Update from XXMSSL_LRN_DETAIL_T . ');
    END;
  
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      'Data Delete Process End from XXMSSL_LRN_SUBINV_LOT. ');
    PRINT_LOG('Start Validating Transaction Type: ' || P_LRN_MRN_TYPE);
  
    IF P_LRN_MRN_TYPE = 'LRN' THEN
      BEGIN
        SELECT TRANSACTION_TYPE_ID
          INTO L_TRANSACTION_TYPE_ID
          FROM MTL_TRANSACTION_TYPES
         WHERE TRANSACTION_TYPE_NAME = 'LRN Transfers'
           AND TRANSACTION_SOURCE_TYPE_ID = 13;
      EXCEPTION
        WHEN OTHERS THEN
          L_TRANSACTION_TYPE_ID := NULL;
      END;
    ELSIF P_LRN_MRN_TYPE = 'MRN' THEN
      BEGIN
        SELECT TRANSACTION_TYPE_ID
          INTO L_TRANSACTION_TYPE_ID
          FROM MTL_TRANSACTION_TYPES
         WHERE TRANSACTION_TYPE_NAME = 'MRN'
           AND TRANSACTION_SOURCE_TYPE_ID = 13;
      EXCEPTION
        WHEN OTHERS THEN
          L_TRANSACTION_TYPE_ID := NULL;
      END;
    END IF;
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := 'Error: ' || P_LRN_MRN_TYPE ||
                         ' Transfers Transaction Type Is Not Defined. ';
      PRINT_LOG('Error: ' || P_LRN_MRN_TYPE ||
                ' Transfers Transaction Type Is Not Defined.');
    END IF;
  
    PRINT_LOG('End Validating Transaction Type: ' || P_LRN_MRN_TYPE ||
              ' and ID: ' || L_TRANSACTION_TYPE_ID);
    PRINT_LOG('Start Validating Current Inventory Month Periods.  ');
  
    SELECT COUNT(1)
      INTO L_COUNT
      FROM ORG_ACCT_PERIODS_V
     WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
       AND TRUNC(SYSDATE) BETWEEN START_DATE AND END_DATE
       AND UPPER(STATUS) = 'OPEN';
  
    IF L_COUNT = 0 THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := 'Error:Period Is Not Open. ';
      PRINT_LOG('Error:Inventory Period Is Not Open.');
    END IF;
  
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      'End Validating Current Inventory Month Periods and Exist Count: ' ||
                      L_COUNT);
    PRINT_LOG('Start Fatching OU Process w.r.t Organization  ');
  
    BEGIN
      SELECT OPERATING_UNIT, ORGANIZATION_NAME
        INTO L_OU, L_ORGANIZATION_NAME
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_OU                := NULL;
        L_ORGANIZATION_NAME := NULL;
    END;
  
    IF L_OU IS NULL THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                         'Error:Invalid Operating Unit. ';
      PRINT_LOG('Error:Invalid Operating Unit.');
    END IF;
  
    PRINT_LOG('End Fatching OU: ' || L_OU ||
              ' Process w.r.t Organization  ');
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      'Start Fatching Sub-Inventory Location from Porfile Option And Validaing the same in system.  ');
  
    IF P_LRN_MRN_TYPE = 'MRN' THEN
      BEGIN
        SELECT FPOV.PROFILE_OPTION_VALUE
          INTO L_PROFILE_SUBINVENTORY
          FROM FND_PROFILE_OPTIONS FPO, FND_PROFILE_OPTION_VALUES FPOV
         WHERE -1 = -1
           AND FPO.PROFILE_OPTION_ID = FPOV.PROFILE_OPTION_ID
           AND FPO.PROFILE_OPTION_NAME = 'XXMSSL_MRN_LOCATION'
           AND FPOV.LEVEL_ID = 10001; -- SITE LEVEL
      EXCEPTION
        WHEN OTHERS THEN
          L_PROFILE_SUBINVENTORY := NULL;
      END;
    
      IF L_PROFILE_SUBINVENTORY IS NOT NULL THEN
        BEGIN
          SELECT MSI.SECONDARY_INVENTORY_NAME
            INTO L_TO_SUBINVENTORY
            FROM MTL_SECONDARY_INVENTORIES MSI
           WHERE -1 = -1
             AND UPPER(MSI.SECONDARY_INVENTORY_NAME) =
                 UPPER(L_PROFILE_SUBINVENTORY)
             AND MSI.ORGANIZATION_ID = P_ORGANIZATION_ID
             AND NVL(MSI.DISABLE_DATE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE);
        EXCEPTION
          WHEN OTHERS THEN
            L_TO_SUBINVENTORY := NULL;
        END;
      ELSE
        L_HEADER_FLAG   := 'E';
        L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                           'Error:To Sub-inventory Does Not Exist In Profile Option: XXMSSL_MRN_LOCATION . ';
        FND_FILE.PUT_LINE(FND_FILE.LOG,
                          'Error:To Sub-inventory Does Not Exist In Profile Option: XXMSSL_MRN_LOCATION .');
      END IF;
    ELSIF P_LRN_MRN_TYPE = 'LRN' THEN
      BEGIN
        SELECT MSI.SECONDARY_INVENTORY_NAME
          INTO L_TO_SUBINVENTORY
          FROM FND_LOOKUP_VALUES            FLV,
               ORG_ORGANIZATION_DEFINITIONS OOD,
               MTL_SECONDARY_INVENTORIES    MSI
         WHERE LOOKUP_TYPE = 'XXMSSL_LRN_MRB_SUBINVENTORY'
           AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
           AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
           AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
           AND FLV.ENABLED_FLAG = 'Y'
           AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE)
           AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
           AND ROWNUM = 1;
      EXCEPTION
        WHEN OTHERS THEN
          L_TO_SUBINVENTORY := NULL;
      END;
    END IF;
  
    IF L_TO_SUBINVENTORY IS NULL THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                         'Error:To Sub-Inventory Does Not Exist In The System For ' ||
                         P_LRN_MRN_TYPE || ' Number: ' || P_LRN_MRN_NUM ||
                         ' And Given Organization ';
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Error: To Sub-Inventory Does Not Exist In The System For ' ||
                        P_LRN_MRN_TYPE || ' Number: ' || P_LRN_MRN_NUM ||
                        ' And Given Organization ');
    END IF;
  
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      'End Fatching Sub-Inventory Location from Porfile Option: ' ||
                      L_PROFILE_SUBINVENTORY ||
                      ' And Validaing the same in system. L_TO_SUBINVENTORY: ' ||
                      L_TO_SUBINVENTORY || ' For ' || P_LRN_MRN_TYPE ||
                      ' Number: ' || P_LRN_MRN_NUM);
  
    IF L_HEADER_FLAG = 'E' THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Calling Error Procedure: p_pragma_records For Header');
      P_PRAGMA_RECORDS('HEADER',
                       P_LRN_MRN_STATUS,
                       P_LRN_MRN_TYPE,
                       P_LRN_MRN_NUM,
                       P_ORGANIZATION_ID,
                       NULL,
                       NULL,
                       L_ERROR_MESSAGE,
                       G_REQUEST_ID);
    END IF;
  
    IF L_HEADER_FLAG = 'S' THEN
      PRINT_LOG('Start Global Intialization for given OU: ' || L_OU ||
                ' and Organization ID: ' || P_ORGANIZATION_ID);
      MO_GLOBAL.SET_POLICY_CONTEXT('S', L_OU);
      INV_GLOBALS.SET_ORG_ID(P_ORGANIZATION_ID);
      MO_GLOBAL.INIT('INV');
      PRINT_LOG('End Global Intialization for given OU: ' || L_OU ||
                ' and Organization ID: ' || P_ORGANIZATION_ID);
      PRINT_LOG(RPAD(' ', 100, ' '));
      PRINT_LOG(RPAD('*', 100, '*'));
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Start Fatching Records - Cursor C_MAIN_CUR For ' ||
                        P_LRN_MRN_TYPE || ' Number: ' || P_LRN_MRN_NUM);
      PRINT_LOG(RPAD('*', 100, '*'));
      PRINT_LOG(RPAD(' ', 100, ' '));
    
      FOR V1 IN C_MAIN_CUR LOOP
        L_ONHAND_QTY    := 0;
        L_HEADER_FLAG   := 'S';
        L_ERROR_MESSAGE := NULL;
      
        SELECT XXMSSL_WIP_MOVE_ORDER_PKG.GET_ONHAND_QTY(V1.ORGANIZATION_ID,
                                                        V1.INVENTORY_ITEM_ID,
                                                        V1.SUBINVENTORY_CODE)
          INTO L_ONHAND_QTY
          FROM DUAL;
      
        PRINT_LOG('Organization Name: ' || L_ORGANIZATION_NAME ||
                  ' - Organization_Id: ' || V1.ORGANIZATION_ID);
        PRINT_LOG('Line_Num: ' || V1.LINE_NUM || ' - Item Name: ' ||
                  V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                  V1.INVENTORY_ITEM_ID);
        PRINT_LOG('Form Sub-Inventory: ' || V1.SUBINVENTORY_CODE ||
                  ' - To Sub-Inventory Location: ' || L_TO_SUBINVENTORY);
        PRINT_LOG('System Current On-Hand I_onhadn_qty:= ' || L_ONHAND_QTY ||
                  '    ' || '- ' || P_LRN_MRN_TYPE ||
                  ' Qty v1.lrn_quantity:= ' || V1.LRN_QUANTITY);
        PRINT_LOG(RPAD('-', 100, '-'));
        PRINT_LOG(RPAD(' ', 100, ' '));
      
        IF L_ONHAND_QTY >= V1.LRN_QUANTITY THEN
          L_RETURN_STATUS   := NULL;
          L_MSG_CNT         := NULL;
          L_MSG_DATA        := NULL;
          L_TRANS_COUNT     := NULL;
          L_INTERFACE_ERROR := NULL;
          
          --delete interface recodrs before insert into interface table V 1.6 
          BEGIN
          DELETE 
          FROM   MTL_TRANSACTION_LOTS_INTERFACE 
          WHERE TRANSACTION_INTERFACE_ID in ( SELECT TRANSACTION_INTERFACE_ID
                                               FROM   MTL_TRANSACTIONS_INTERFACE  
                                              WHERE TRANSACTION_REFERENCE = v1.lrn_no
                                              AND organization_id = v1.organization_id
                                              AND inventory_item_id =  v1.inventory_item_id
                                              AND SUBINVENTORY_CODE = V1.SUBINVENTORY_CODE);
            
           DELETE FROM   MTL_TRANSACTIONS_INTERFACE  
           WHERE TRANSACTION_REFERENCE = v1.lrn_no
           AND organization_id = v1.organization_id
           AND inventory_item_id =  v1.inventory_item_id
           AND SUBINVENTORY_CODE = V1.SUBINVENTORY_CODE;
           
          EXCEPTION WHEN 
              OTHERS THEN 
             PRINT_LOG('error while delete record from interface table '||sqlerrm);
         END ;
         
         
        
          SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
            INTO L_TRANSACTION_INTERFACE_ID
            FROM DUAL;
        
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'Start Insertion Process Records For Transaction Type: ' ||
                            P_LRN_MRN_TYPE ||
                            ' into Interface Table For Transaction_Interface_Id: ' ||
                            L_TRANSACTION_INTERFACE_ID);
        
          IF P_LRN_MRN_TYPE = 'LRN' THEN
            BEGIN
              INSERT INTO MTL_TRANSACTIONS_INTERFACE
                (CREATED_BY,
                 CREATION_DATE,
                 INVENTORY_ITEM_ID,
                 LAST_UPDATED_BY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATE_LOGIN,
                 LOCK_FLAG,
                 ORGANIZATION_ID,
                 PROCESS_FLAG,
                 SOURCE_CODE,
                 SOURCE_HEADER_ID,
                 SOURCE_LINE_ID,
                 SUBINVENTORY_CODE,
                 TRANSACTION_DATE,
                 TRANSACTION_HEADER_ID,
                 TRANSACTION_INTERFACE_ID,
                 TRANSACTION_MODE,
                 TRANSACTION_QUANTITY,
                 TRANSACTION_TYPE_ID,
                 TRANSACTION_UOM,
                 TRANSFER_SUBINVENTORY,
                 TRANSACTION_REFERENCE)
              VALUES
                (L_USER_ID,
                 SYSDATE,
                 V1.INVENTORY_ITEM_ID,
                 L_USER_ID,
                 SYSDATE,
                 L_LOGIN_ID,
                 2,
                 P_ORGANIZATION_ID,
                 1,
                 'LRN Subinventory Transfer',
                 1,
                 2,
                 V1.SUBINVENTORY_CODE,
                 SYSDATE,
                 L_TRANSACTION_INTERFACE_ID,
                 L_TRANSACTION_INTERFACE_ID,
                 3,
                 V1.LRN_QUANTITY,
                 L_TRANSACTION_TYPE_ID,
                 V1.UOM,
                 L_TO_SUBINVENTORY,
                 P_LRN_MRN_NUM);
            EXCEPTION
              WHEN OTHERS THEN
                L_HEADER_FLAG   := 'E';
                L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                   'Error While Insertion the Process Records For Transaction Type: ' ||
                                   P_LRN_MRN_TYPE ||
                                   ' into Interface Table For Transaction_Interface_Id: ' ||
                                   L_TRANSACTION_INTERFACE_ID;
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While Insertion the Process Records For Transaction Type: ' ||
                                  P_LRN_MRN_TYPE ||
                                  ' into Interface Table For Transaction_Interface_Id: ' ||
                                  L_TRANSACTION_INTERFACE_ID);
            END;
          
            /*FOR LOG PURPOSE */
            BEGIN
              INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
                (CREATED_BY,
                 CREATION_DATE,
                 INVENTORY_ITEM_ID,
                 LAST_UPDATED_BY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATE_LOGIN,
                 LOCK_FLAG,
                 ORGANIZATION_ID,
                 PROCESS_FLAG,
                 SOURCE_CODE,
                 SOURCE_HEADER_ID,
                 SOURCE_LINE_ID,
                 SUBINVENTORY_CODE,
                 TRANSACTION_DATE,
                 TRANSACTION_HEADER_ID,
                 TRANSACTION_INTERFACE_ID,
                 TRANSACTION_MODE,
                 TRANSACTION_QUANTITY,
                 TRANSACTION_TYPE_ID,
                 TRANSACTION_UOM,
                 TRANSFER_SUBINVENTORY,
                 TRANSACTION_REFERENCE)
              VALUES
                (L_USER_ID,
                 SYSDATE,
                 V1.INVENTORY_ITEM_ID,
                 L_USER_ID,
                 SYSDATE,
                 L_LOGIN_ID,
                 2,
                 P_ORGANIZATION_ID,
                 1,
                 'LRN Subinventory Transfer',
                 1,
                 2,
                 V1.SUBINVENTORY_CODE,
                 SYSDATE,
                 L_TRANSACTION_INTERFACE_ID,
                 L_TRANSACTION_INTERFACE_ID,
                 3,
                 V1.LRN_QUANTITY,
                 L_TRANSACTION_TYPE_ID,
                 V1.UOM,
                 L_TO_SUBINVENTORY,
                 P_LRN_MRN_NUM);
            EXCEPTION
              WHEN OTHERS THEN
                L_HEADER_FLAG   := 'E';
                L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                   'Error While Insertion the Process Records For Transaction Type: ' ||
                                   P_LRN_MRN_TYPE ||
                                   ' into Backup Table:XXMSSL_LRN_MTL_TRANS_INTERFACE For Transaction_Interface_Id: ' ||
                                   L_TRANSACTION_INTERFACE_ID;
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While Insertion the Process Records For Transaction Type: ' ||
                                  P_LRN_MRN_TYPE ||
                                  ' into Backup Table:XXMSSL_LRN_MTL_TRANS_INTERFACE For Transaction_Interface_Id: ' ||
                                  L_TRANSACTION_INTERFACE_ID);
            END;
          ELSIF P_LRN_MRN_TYPE = 'MRN' THEN
            BEGIN
              INSERT INTO MTL_TRANSACTIONS_INTERFACE
                (CREATED_BY,
                 CREATION_DATE,
                 INVENTORY_ITEM_ID,
                 LAST_UPDATED_BY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATE_LOGIN,
                 LOCK_FLAG,
                 ORGANIZATION_ID,
                 PROCESS_FLAG,
                 SOURCE_CODE,
                 SOURCE_HEADER_ID,
                 SOURCE_LINE_ID,
                 SUBINVENTORY_CODE,
                 TRANSACTION_DATE,
                 TRANSACTION_HEADER_ID,
                 TRANSACTION_INTERFACE_ID,
                 TRANSACTION_MODE,
                 TRANSACTION_QUANTITY,
                 TRANSACTION_TYPE_ID,
                 TRANSACTION_UOM,
                 TRANSFER_SUBINVENTORY,
                 TRANSACTION_REFERENCE)
              VALUES
                (L_USER_ID,
                 SYSDATE,
                 V1.INVENTORY_ITEM_ID,
                 L_USER_ID,
                 SYSDATE,
                 L_LOGIN_ID,
                 2,
                 P_ORGANIZATION_ID,
                 1,
                 'MRN',
                 1,
                 2,
                 V1.SUBINVENTORY_CODE,
                 SYSDATE,
                 L_TRANSACTION_INTERFACE_ID,
                 L_TRANSACTION_INTERFACE_ID,
                 3,
                 V1.LRN_QUANTITY,
                 L_TRANSACTION_TYPE_ID,
                 V1.UOM,
                 L_TO_SUBINVENTORY,
                 P_LRN_MRN_NUM);
            EXCEPTION
              WHEN OTHERS THEN
                L_HEADER_FLAG   := 'E';
                L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                   'Error While Insertion the Process Records For Transaction Type: ' ||
                                   P_LRN_MRN_TYPE ||
                                   ' into Interface Table For Transaction_Interface_Id: ' ||
                                   L_TRANSACTION_INTERFACE_ID;
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While Insertion the Process Records For Transaction Type: ' ||
                                  P_LRN_MRN_TYPE ||
                                  ' into Interface Table For Transaction_Interface_Id: ' ||
                                  L_TRANSACTION_INTERFACE_ID);
            END;
          
            /*FOR LOG PURPOSE */
            BEGIN
              INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
                (CREATED_BY,
                 CREATION_DATE,
                 INVENTORY_ITEM_ID,
                 LAST_UPDATED_BY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATE_LOGIN,
                 LOCK_FLAG,
                 ORGANIZATION_ID,
                 PROCESS_FLAG,
                 SOURCE_CODE,
                 SOURCE_HEADER_ID,
                 SOURCE_LINE_ID,
                 SUBINVENTORY_CODE,
                 TRANSACTION_DATE,
                 TRANSACTION_HEADER_ID,
                 TRANSACTION_INTERFACE_ID,
                 TRANSACTION_MODE,
                 TRANSACTION_QUANTITY,
                 TRANSACTION_TYPE_ID,
                 TRANSACTION_UOM,
                 TRANSFER_SUBINVENTORY,
                 TRANSACTION_REFERENCE)
              VALUES
                (L_USER_ID,
                 SYSDATE,
                 V1.INVENTORY_ITEM_ID,
                 L_USER_ID,
                 SYSDATE,
                 L_LOGIN_ID,
                 2,
                 P_ORGANIZATION_ID,
                 1,
                 'MRN',
                 1,
                 2,
                 V1.SUBINVENTORY_CODE,
                 SYSDATE,
                 L_TRANSACTION_INTERFACE_ID,
                 L_TRANSACTION_INTERFACE_ID,
                 3,
                 V1.LRN_QUANTITY,
                 L_TRANSACTION_TYPE_ID,
                 V1.UOM,
                 L_TO_SUBINVENTORY,
                 P_LRN_MRN_NUM);
            EXCEPTION
              WHEN OTHERS THEN
                L_HEADER_FLAG   := 'E';
                L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                   'Error While Insertion the Process Records For Transaction Type: ' ||
                                   P_LRN_MRN_TYPE ||
                                   ' into Backup Table:XXMSSL_LRN_MTL_TRANS_INTERFACE For Transaction_Interface_Id: ' ||
                                   L_TRANSACTION_INTERFACE_ID;
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While Insertion the Process Records For Transaction Type: ' ||
                                  P_LRN_MRN_TYPE ||
                                  ' into Backup Table:XXMSSL_LRN_MTL_TRANS_INTERFACE For Transaction_Interface_Id: ' ||
                                  L_TRANSACTION_INTERFACE_ID);
            END;
          END IF;
        
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'End Insertion Process Records For Transaction Type: ' ||
                            P_LRN_MRN_TYPE ||
                            ' into Interface Table For Transaction_Interface_Id: ' ||
                            L_TRANSACTION_INTERFACE_ID);
          /***************** CHECK ITEM IS LOT CONTROLLED ***************/
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'Start Validating the Item Master Lot Controlled For Item ID: ' ||
                            V1.INVENTORY_ITEM_ID ||
                            ' And Organization_id: ' || P_ORGANIZATION_ID);
        
          SELECT COUNT(1)
            INTO L_COUNT
            FROM MTL_SYSTEM_ITEMS_B
           WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
             AND INVENTORY_ITEM_ID = V1.INVENTORY_ITEM_ID
             AND LOT_CONTROL_CODE = 2;
        
          IF L_COUNT > 0 THEN
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'Item Master Lot Control Exist L_COUNT: ' ||
                              L_COUNT || ' For Item ID: ' ||
                              V1.INVENTORY_ITEM_ID ||
                              ' And Organization_id: ' || P_ORGANIZATION_ID);
            L_REMAINING_QUANTITY := V1.LRN_QUANTITY;
            PRINT_LOG(' L_REMAINING_QUANTITY: ' || L_REMAINING_QUANTITY);
            PRINT_LOG(RPAD(' ', 100, ' '));
            PRINT_LOG(RPAD('*', 100, '*'));
            APPS.FND_FILE.PUT_LINE(FND_FILE.LOG,
                                   'Start Fatching Records For Transaction Type: ' ||
                                   P_LRN_MRN_TYPE ||
                                   ' - Cursor: C_LOT - Item Lot Control For Line_Num: ' ||
                                   V1.LINE_NUM || ' - Item Name: ' ||
                                   V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                                   V1.INVENTORY_ITEM_ID ||
                                   ' - Sub-Inventory: ' ||
                                   V1.SUBINVENTORY_CODE);
            PRINT_LOG(RPAD('*', 100, '*'));
            PRINT_LOG(RPAD(' ', 100, ' '));
          
            FOR V_LOT IN C_LOT(V1.INVENTORY_ITEM_ID, V1.SUBINVENTORY_CODE) LOOP
              L_TRANSACTION_QUANTITY := NULL;
              PRINT_LOG('L_REMAINING_QUANTITY: ' || L_REMAINING_QUANTITY);
              PRINT_LOG('Lot Qty: ' || V_LOT.TRANSACTION_QUANTITY);
              PRINT_LOG('Lot No.: ' || V_LOT.LOT_NUMBER);
            
              IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
                L_REMAINING_QUANTITY   := 0;
              ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
                L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
                L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                          V_LOT.TRANSACTION_QUANTITY;
              END IF;
            
              PRINT_LOG('L_Remaining_Quantity: ' || L_REMAINING_QUANTITY);
              PRINT_LOG('L_Transaction_Quantity: ' ||
                        L_TRANSACTION_QUANTITY);
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                'Start Insertion Process Records For Transaction Type: ' ||
                                P_LRN_MRN_TYPE ||
                                ' into LOT Interface Table For V_LOT.LOT_NUMBER: ' ||
                                V_LOT.LOT_NUMBER);
            
              BEGIN
                INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
                  (TRANSACTION_INTERFACE_ID,
                   LOT_NUMBER,
                   TRANSACTION_QUANTITY,
                   LAST_UPDATE_DATE,
                   LAST_UPDATED_BY,
                   CREATION_DATE,
                   CREATED_BY)
                VALUES
                  (L_TRANSACTION_INTERFACE_ID,
                   V_LOT.LOT_NUMBER,
                   L_TRANSACTION_QUANTITY,
                   SYSDATE,
                   L_USER_ID,
                   SYSDATE,
                   L_USER_ID);
              EXCEPTION
                WHEN OTHERS THEN
                  L_HEADER_FLAG   := 'E';
                  L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                     'Error While Insertion the Process Records For Transaction Type: ' ||
                                     P_LRN_MRN_TYPE ||
                                     ' into LOT Interface Table For V_LOT.LOT_NUMBER: ' ||
                                     V_LOT.LOT_NUMBER;
                  FND_FILE.PUT_LINE(FND_FILE.LOG,
                                    'Error While Insertion the Process Records For Transaction Type: ' ||
                                    P_LRN_MRN_TYPE ||
                                    ' into LOT Interface Table For V_LOT.LOT_NUMBER: ' ||
                                    V_LOT.LOT_NUMBER);
              END;
            
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                'END Insertion Process Records For Transaction Type: ' ||
                                P_LRN_MRN_TYPE ||
                                ' into LOT Interface Table For V_LOT.LOT_NUMBER: ' ||
                                V_LOT.LOT_NUMBER);
            
              /*  ---vchnage for  v 1.5  
              FND_FILE.PUT_LINE
                   (FND_FILE.LOG,
                       'Start Insertion Process Records For Transaction Type: '
                    || P_LRN_MRN_TYPE
                    || ' into LOT Staging Table: XXMSSL_LRN_SUBINV_LOT '
                   );
              
                BEGIN
                   INSERT INTO XXMSSL.XXMSSL_LRN_SUBINV_LOT
                               (ORGANIZATION_ID, LRN_NO,
                                INVENTORY_ITEM_ID,
                                SUBINVENTORY_CODE, LOT_NUMBER,
                                LOT_QUANTITY, CREATION_DATE,
                                CREATED_BY, LINE_NUMBER
                               )
                        VALUES (P_ORGANIZATION_ID, P_LRN_MRN_NUM,
                                V1.INVENTORY_ITEM_ID,
                                L_TO_SUBINVENTORY, V_LOT.LOT_NUMBER,
                                L_TRANSACTION_QUANTITY, SYSDATE,
                                L_USER_ID, V1.LINE_NUM
                               );
                EXCEPTION
                   WHEN OTHERS
                   THEN
                      L_HEADER_FLAG := 'E';
                      L_ERROR_MESSAGE :=
                            L_ERROR_MESSAGE
                         || 'Error While Insertion the Process Records For Transaction Type: '
                         || P_LRN_MRN_TYPE
                         || ' into LOT Staging Table: XXMSSL_LRN_SUBINV_LOT ';
                      FND_FILE.PUT_LINE
                         (FND_FILE.LOG,
                             'Error While Insertion the Process Records For Transaction Type: '
                          || P_LRN_MRN_TYPE
                          || ' into LOT Staging Table: XXMSSL_LRN_SUBINV_LOT '
                         );
                END;
              
                FND_FILE.PUT_LINE
                   (FND_FILE.LOG,
                       'End Insertion Process Records For Transaction Type: '
                    || P_LRN_MRN_TYPE
                    || ' into LOT Staging Table: XXMSSL_LRN_SUBINV_LOT '
                   );*/
            
              IF L_REMAINING_QUANTITY = 0 THEN
                PRINT_LOG('l_remaining_quantity: ' || L_REMAINING_QUANTITY);
                EXIT;
              END IF;
            END LOOP;
          END IF;
        
          PRINT_LOG(RPAD(' ', 100, ' '));
          PRINT_LOG(RPAD('-', 100, '-'));
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'Calling API Process:Inv_Txn_Manager_Pub.Process_Transactions For Transaction Type: ' ||
                            P_LRN_MRN_TYPE || ' .');
          PRINT_LOG(RPAD('-', 100, '-'));
          PRINT_LOG(RPAD(' ', 100, ' '));
          V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                                P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                                P_COMMIT           => FND_API.G_TRUE,
                                                                P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                                X_RETURN_STATUS    => L_RETURN_STATUS,
                                                                X_MSG_COUNT        => L_MSG_CNT,
                                                                X_MSG_DATA         => L_MSG_DATA,
                                                                X_TRANS_COUNT      => L_TRANS_COUNT,
                                                                P_TABLE            => 1,
                                                                P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'End API Process:Inv_Txn_Manager_Pub.Process_Transactions For Transaction Type: ' ||
                            P_LRN_MRN_TYPE || ' .');
          PRINT_LOG('API Return Status: ' || L_RETURN_STATUS);
          PRINT_LOG('API Message Cnt: ' || NVL(L_MSG_CNT, 0));
        
          IF (NVL(L_RETURN_STATUS, 'E') <> 'S') THEN
            L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
          
            FOR I IN 1 .. L_MSG_CNT LOOP
              FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                              P_ENCODED       => 'F',
                              P_DATA          => L_MSG_DATA,
                              P_MSG_INDEX_OUT => X_MSG_INDEX);
              X_MSG := X_MSG || '.' || L_MSG_DATA;
            END LOOP;
          
            IF P_LRN_MRN_TYPE = 'LRN' THEN
              BEGIN
                SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
                  INTO L_INTERFACE_ERROR
                  FROM MTL_TRANSACTIONS_INTERFACE
                 WHERE TRANSACTION_INTERFACE_ID =
                       L_TRANSACTION_INTERFACE_ID
                   AND SOURCE_CODE = 'LRN Subinventory Transfer';
              EXCEPTION
                WHEN OTHERS THEN
                  L_INTERFACE_ERROR := NULL;
              END;
            ELSIF P_LRN_MRN_TYPE = 'MRN' THEN
              BEGIN
                SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
                  INTO L_INTERFACE_ERROR
                  FROM MTL_TRANSACTIONS_INTERFACE
                 WHERE TRANSACTION_INTERFACE_ID =
                       L_TRANSACTION_INTERFACE_ID
                   AND SOURCE_CODE = 'MRN';
              EXCEPTION
                WHEN OTHERS THEN
                  L_INTERFACE_ERROR := NULL;
              END;
            END IF;
          
            ERRBUF := X_MSG || ' . and Interface Error Message:' ||
                      L_INTERFACE_ERROR;
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'API Error in Subinventory Transfer For Transaction Type: ' ||
                              P_LRN_MRN_TYPE ||
                              ' And  Transaction_Interface_Id:- ' ||
                              L_TRANSACTION_INTERFACE_ID ||
                              'API Error Message: ' || X_MSG ||
                              ' . and Interface Error Message:' ||
                              L_INTERFACE_ERROR);
            L_ERROR_MESSAGE := SUBSTR(L_ERROR_MESSAGE ||
                                      ' SUBMIT: For Transaction Type: ' ||
                                      P_LRN_MRN_TYPE ||
                                      ' L_Transaction_Interface_Id ' ||
                                      L_TRANSACTION_INTERFACE_ID || ERRBUF,
                                      1,
                                      2000);
          
            BEGIN
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                'Calling Error Procedure: p_pragma_records For Line');
              P_PRAGMA_RECORDS('LINE',
                               P_LRN_MRN_STATUS,
                               P_LRN_MRN_TYPE,
                               P_LRN_MRN_NUM,
                               P_ORGANIZATION_ID,
                               V1.LINE_NUM,
                               NULL,
                               L_ERROR_MESSAGE,
                               G_REQUEST_ID);
            EXCEPTION
              WHEN OTHERS THEN
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While Update the API Error Message In Staging 
                         table xxmssl_lrn_detail_t for Transaction Type: ' ||
                                  P_LRN_MRN_TYPE || '  No.: ' ||
                                  P_LRN_MRN_NUM || ' and  Line Num: ' ||
                                  V1.LINE_NUM);
            END;
          ELSIF NVL(L_RETURN_STATUS, 'E') = 'S' THEN
            ERRBUF := NULL;
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'LRN/MRN Sub-Inventory Transfer Successfully Complete For Transaction Type: ' ||
                              P_LRN_MRN_TYPE || '  No: ' || P_LRN_MRN_NUM ||
                              '- Line_Num: ' || V1.LINE_NUM ||
                              ' - Item Name: ' || V1.ITEM_CODE ||
                              ' - Inventory_Item_Id: ' ||
                              V1.INVENTORY_ITEM_ID);
          
            BEGIN
              UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
                 SET SUBINVENTORY_TRANSFER = 'Y', REQUEST_ID = G_REQUEST_ID,ERROR_MESSAGE =NULL
               WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
                 AND LRN_NO = P_LRN_MRN_NUM
                 AND LINE_NUM = V1.LINE_NUM;
            EXCEPTION
              WHEN OTHERS THEN
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While updating the Success Flag in staging table XXMSSL_LRN_DETAIL_T For Transaction Type: ' ||
                                  P_LRN_MRN_TYPE || '  No: ' ||
                                  P_LRN_MRN_NUM || ' and LINE No: ' ||
                                  V1.LINE_NUM);
            END;
          
            IF P_LRN_MRN_TYPE = 'MRN' THEN
              INSERT_MRN_BALANCE(P_ORGANIZATION_ID => P_ORGANIZATION_ID,
                                 P_LRN_NUMBER      => P_LRN_MRN_NUM,
                                 P_LINE_NUMBER     => V1.LINE_NUM,
                                 P_RET_STATUS      => L_RET_VAL,
                                 P_RET_MSG         => L_RETURN_MSG);
            END IF;
          END IF;
        ELSE
          L_HEADER_FLAG := 'E';
         
          L_ERROR_MESSAGE := 'Error: Stock Qty Is Less Then ' ||
                             P_LRN_MRN_TYPE || '  Qty - I_onhadn_qty:= ' ||
                             L_ONHAND_QTY || '    ' ||
                             ' v1.lrn_quantity:= ' || V1.LRN_QUANTITY;
            PRINT_LOG(L_ERROR_MESSAGE);
        
          BEGIN
          
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'Calling Error Procedure: p_pragma_records For Line');
            P_PRAGMA_RECORDS('LINE',
                             P_LRN_MRN_STATUS,
                             P_LRN_MRN_TYPE,
                             P_LRN_MRN_NUM,
                             P_ORGANIZATION_ID,
                             V1.LINE_NUM,
                             NULL,
                             L_ERROR_MESSAGE,
                             G_REQUEST_ID);
                   
          EXCEPTION
            WHEN OTHERS THEN
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                'Error While updating the Error Message in staging table XXMSSL_LRN_DETAIL_T For Transaction Type: ' ||
                                P_LRN_MRN_TYPE || '  No: ' || P_LRN_MRN_NUM ||
                                ' and LINE No: ' || V1.LINE_NUM);
          END;
        commit;
--          IF L_HEADER_FLAG = 'E' THEN
--            EXIT;
--          END IF;
        END IF;
      END LOOP;
    
      PRINT_LOG('L_HEADER_FLAG: ' || L_HEADER_FLAG);
      
      
      IF L_HEADER_FLAG = 'E' THEN
       RETCODE :=2;
        PRINT_LOG('Error: ' || L_HEADER_FLAG);
      ELSIF L_HEADER_FLAG = 'S' THEN
        COMMIT;
        PRINT_LOG('COMMIT: ' || L_HEADER_FLAG);
      END IF;
    ELSE
      PRINT_LOG('Error: L_HEADER_FLAG: ' || L_HEADER_FLAG);
    END IF;
  
   commit; 
     
 P_GENERATE_OUTPUT(P_LRN_MRN_NUM,
                      P_LRN_MRN_STATUS,
                      P_LRN_MRN_TYPE,
                      P_ORGANIZATION_ID,
                      L_ORGANIZATION_NAME,
                      L_TO_SUBINVENTORY,
                      G_REQUEST_ID);
  EXCEPTION
    WHEN OTHERS THEN
      ERRBUF := 'EXCEPTION IN SUBINVENTORY_TRANSFER:' || SQLERRM;
      PRINT_LOG('EXCEPTION IN SUBINVENTORY_TRANSFER:' || SQLERRM);
  END LRN_SUBINVENTORY_TRANSFER;
  /**********************************************************************************************************
  REM COPYRIGHT (C) 2025 MOTHERSON ALL RIGHTS RESERVED.
  REM *******************************************************************************************************
  REM FILE NAME                : XXMSSL_LRN_PKG.LRN_REJECT_SUBINVENTORY_TFR
  REM DOC REF(S)               : REFER OLD PACKAGE XXMSSL_LRN_PKG
  REM PROJECT                  : MOTHERSON PROJECT
  REM DESCRIPTION              :XXMSSL: LRN REJECT-RETURN SUB INVENTORY TRANSFER PROGRAM CEMLI-C062, AUTHOR: RAVISH CHAUHAN
  REM
  REM CHANGE HISTORY INFORMATION
  REM --------------------------
  REM VERSION  DATE         AUTHOR           CHANGE REFERENCE / DESCRIPTION
  REM -------  -----------  ---------------  ----------------------------------------
  REM 1.0     07-JAN-2025     VIKAS CHAUHAN   INITIAL VERSION
  REM *******************************************************************************************************/
  PROCEDURE LRN_REJECT_SUBINVENTORY_TFR(ERRBUF            OUT VARCHAR2,
                                        RETCODE           OUT VARCHAR2,
                                        P_LRN_STATUS      VARCHAR2,
                                        P_LRN_ACTION_TYPE VARCHAR2,
                                        P_LRN_NUMBER      VARCHAR2,
                                        P_ORGANIZATION_ID NUMBER) IS
    L_USER_ID                  NUMBER := FND_PROFILE.VALUE('USER_ID');
    L_LOGIN_ID                 NUMBER := FND_PROFILE.VALUE('LOGIN_ID');
    L_TRANSACTION_INTERFACE_ID NUMBER;
    V_RET_VAL                  NUMBER;
    L_RETURN_STATUS            VARCHAR2(100);
    L_MSG_CNT                  NUMBER;
    L_MSG_DATA                 VARCHAR2(4000);
    L_TRANS_COUNT              NUMBER;
    X_MSG_INDEX                NUMBER;
    X_MSG                      VARCHAR2(4000);
    L_TO_SUBINVENTORY          VARCHAR2(50);
    L_COUNT                    NUMBER;
    L_TRANSACTION_TYPE_ID      NUMBER;
    L_TRANSACTION_QUANTITY     NUMBER;
    L_REMAINING_QUANTITY       NUMBER;
    L_AVIL_ONHAND              NUMBER;
    L_VAL_FALG                 VARCHAR2(1);
    L_OU                       NUMBER;
    L_ERROR_MESSAGE            VARCHAR2(4000);
    L_HEADER_FLAG              VARCHAR2(1);
    L_INTERFACE_ERROR          VARCHAR2(4000);
    L_ORGANIZATION_NAME        VARCHAR2(240);
    L_LRN_MRN_TYPE             VARCHAR2(10);
  
    CURSOR C1 IS
      SELECT XLD.*
        FROM XXMSSL.XXMSSL_LRN_DETAIL_T XLD, XXMSSL.XXMSSL_LRN_HEADER_T XLH
       WHERE XLD.ORGANIZATION_ID = XLH.ORGANIZATION_ID
         AND XLD.LRN_NO = XLH.LRN_NO
         AND XLD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND XLD.LRN_NO = P_LRN_NUMBER;
  
    --added for v1.6 
    CURSOR C_LOT(P_INVENTORY_ITEM_ID NUMBER,
                 P_SUBINVENTORY_CODE IN VARCHAR2) IS
      SELECT *
        FROM (SELECT MLN.LOT_NUMBER,
                     MLN.CREATION_DATE,
                     XXMSSL_LRN_PKG.GET_OHQTY(MOQ.INVENTORY_ITEM_ID,
                                              MOQ.ORGANIZATION_ID,
                                              MOQ.SUBINVENTORY_CODE,
                                              MLN.LOT_NUMBER,
                                              'ATT') TRANSACTION_QUANTITY
                FROM MTL_ONHAND_QUANTITIES MOQ, MTL_LOT_NUMBERS MLN
               WHERE MOQ.ORGANIZATION_ID = MLN.ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = MLN.INVENTORY_ITEM_ID
                 AND MLN.LOT_NUMBER = MOQ.LOT_NUMBER
                 AND MOQ.ORGANIZATION_ID = P_ORGANIZATION_ID
                 AND MOQ.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
                 AND SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
               GROUP BY MLN.LOT_NUMBER,
                        MOQ.INVENTORY_ITEM_ID,
                        MOQ.ORGANIZATION_ID,
                        SUBINVENTORY_CODE,
                        MLN.CREATION_DATE)
       WHERE TRANSACTION_QUANTITY > 0
       ORDER BY CREATION_DATE;
  
    /*   ---v 1.8
    CURSOR C_LOT (
        P_INVENTORY_ITEM_ID        NUMBER,
        P_SUBINVENTORY_CODE   IN   VARCHAR2,
        P_LINE_NUM                 NUMBER
     )
     IS
        SELECT   XXLOT.LOT_NUMBER, XXLOT.CREATION_DATE,
                 SUM (XXLOT.LOT_QUANTITY) TRANSACTION_QUANTITY
            FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT
           WHERE 1 = 1
             AND XXLOT.LRN_NO = P_LRN_NUMBER
             AND XXLOT.LINE_NUMBER = P_LINE_NUM
             AND XXLOT.ORGANIZATION_ID = P_ORGANIZATION_ID
             AND XXLOT.INVENTORY_ITEM_ID = P_INVENTORY_ITEM_ID
             AND XXLOT.SUBINVENTORY_CODE = P_SUBINVENTORY_CODE
        GROUP BY XXLOT.LOT_NUMBER, XXLOT.CREATION_DATE;*/
  BEGIN
    L_LRN_MRN_TYPE        := 'LRN';
    G_LRN_NO              := P_LRN_NUMBER;
    L_HEADER_FLAG         := 'S';
    L_ERROR_MESSAGE       := NULL;
    L_INTERFACE_ERROR     := NULL;
    L_TRANSACTION_TYPE_ID := NULL;
    L_COUNT               := 0;
    L_TO_SUBINVENTORY     := NULL;
    L_ORGANIZATION_NAME   := NULL;
    G_REQUEST_ID          := FND_GLOBAL.CONC_REQUEST_ID;
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('*', 100, '*'));
    FND_FILE.PUT_LINE(2, 'Start Reject Subinventory Transfer Process');
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD('*', 100, '*'));
    APPS.FND_FILE.PUT_LINE(APPS.FND_FILE.OUTPUT, RPAD(' ', 100, ' '));
    PRINT_LOG(RPAD('*', 100, '*'));
    FND_FILE.PUT_LINE(1, 'Start Reject Subinventory Transfer Process');
    PRINT_LOG(RPAD('*', 100, '*'));
    PRINT_LOG(RPAD(' ', 100, ' '));
    PRINT_LOG('Program Request ID: ' || G_REQUEST_ID);
    PRINT_LOG('Action Type: ' || P_LRN_ACTION_TYPE || ' Number: ' ||
              P_LRN_NUMBER);
    PRINT_LOG('Action Type: ' || P_LRN_ACTION_TYPE);
    PRINT_LOG('Current Status: ' || P_LRN_STATUS);
    PRINT_LOG('Organization ID: ' || P_ORGANIZATION_ID);
    PRINT_LOG('Start Validating Transaction Type:LRN Transfers ');
  
    BEGIN
      SELECT TRANSACTION_TYPE_ID
        INTO L_TRANSACTION_TYPE_ID
        FROM MTL_TRANSACTION_TYPES
       WHERE TRANSACTION_TYPE_NAME = 'LRN Transfers'
         AND TRANSACTION_SOURCE_TYPE_ID = 13;
    EXCEPTION
      WHEN OTHERS THEN
        L_TRANSACTION_TYPE_ID := NULL;
    END;
  
    IF L_TRANSACTION_TYPE_ID IS NULL THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := 'Error: ' || L_LRN_MRN_TYPE ||
                         ' Transfers Transaction Type Is Not Defined. ';
      PRINT_LOG('Error: ' || L_LRN_MRN_TYPE ||
                ' Transfers Transaction Type Is Not Defined.');
    END IF;
  
    PRINT_LOG('End Validating Transaction Type: ' || L_LRN_MRN_TYPE ||
              ' and ID: ' || L_TRANSACTION_TYPE_ID);
    PRINT_LOG('Start Validating Current Inventory Month Periods.  ');
  
    SELECT COUNT(1)
      INTO L_COUNT
      FROM ORG_ACCT_PERIODS_V
     WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
       AND TRUNC(SYSDATE) BETWEEN START_DATE AND END_DATE
       AND UPPER(STATUS) = 'OPEN';
  
    IF L_COUNT = 0 THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := 'Error:Period Is Not Open. ';
      PRINT_LOG('Error:Inventory Period Is Not Open.');
    END IF;
  
    FND_FILE.PUT_LINE(FND_FILE.LOG,
                      'End Validating Current Inventory Month Periods and Exist Count: ' ||
                      L_COUNT);
    PRINT_LOG('Start Fatching OU Process w.r.t Organization  ');
  
    BEGIN
      SELECT OPERATING_UNIT, ORGANIZATION_NAME
        INTO L_OU, L_ORGANIZATION_NAME
        FROM ORG_ORGANIZATION_DEFINITIONS
       WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
    EXCEPTION
      WHEN OTHERS THEN
        L_OU                := NULL;
        L_ORGANIZATION_NAME := NULL;
    END;
  
    IF L_OU IS NULL THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                         'Error:Invalid Operating Unit. ';
      PRINT_LOG('Error:Invalid Operating Unit.');
    END IF;
  
    PRINT_LOG('End Fatching OU: ' || L_OU ||
              ' Process w.r.t Organization  ');
    PRINT_LOG('Start Fatching Sub-Inventory Location: ' ||
              L_TO_SUBINVENTORY);
  
    BEGIN
      SELECT MSI.SECONDARY_INVENTORY_NAME
        INTO L_TO_SUBINVENTORY
        FROM FND_LOOKUP_VALUES            FLV,
             ORG_ORGANIZATION_DEFINITIONS OOD,
             MTL_SECONDARY_INVENTORIES    MSI
       WHERE LOOKUP_TYPE = 'XXMSSL_LRN_MRB_SUBINVENTORY'
         AND FLV.DESCRIPTION = OOD.ORGANIZATION_CODE
         AND OOD.ORGANIZATION_ID = P_ORGANIZATION_ID
         AND MSI.SECONDARY_INVENTORY_NAME = FLV.TAG
         AND FLV.ENABLED_FLAG = 'Y'
         AND NVL(FLV.START_DATE_ACTIVE, TRUNC(SYSDATE)) <= TRUNC(SYSDATE)
         AND NVL(FLV.END_DATE_ACTIVE, TRUNC(SYSDATE)) >= TRUNC(SYSDATE)
         AND ROWNUM = 1;
    EXCEPTION
      WHEN OTHERS THEN
        L_TO_SUBINVENTORY := NULL;
    END;
  
    IF L_TO_SUBINVENTORY IS NULL THEN
      L_HEADER_FLAG   := 'E';
      L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                         'Error:To Sub-Inventory Does Not Exist In The System For ' ||
                         L_LRN_MRN_TYPE || ' Number: ' || P_LRN_NUMBER ||
                         ' And Given Organization ';
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Error: To Sub-Inventory Does Not Exist In The System For ' ||
                        L_LRN_MRN_TYPE || ' Number: ' || P_LRN_NUMBER ||
                        ' And Given Organization ');
    END IF;
  
    PRINT_LOG('End Fatching Sub-Inventory Location: ' || L_TO_SUBINVENTORY);
  
    IF L_HEADER_FLAG = 'E' THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG,
                        'Calling Error Procedure: p_pragma_records For Header');
      P_PRAGMA_RECORDS('HEADER',
                       P_LRN_STATUS,
                       'LRN',
                       P_LRN_NUMBER,
                       P_ORGANIZATION_ID,
                       NULL,
                       NULL,
                       L_ERROR_MESSAGE,
                       G_REQUEST_ID);
    END IF;
  
    IF L_HEADER_FLAG = 'S' THEN
      PRINT_LOG('Start Global Intialization for given OU: ' || L_OU ||
                ' and Organization ID: ' || P_ORGANIZATION_ID);
      MO_GLOBAL.SET_POLICY_CONTEXT('S', L_OU);
      INV_GLOBALS.SET_ORG_ID(P_ORGANIZATION_ID);
      MO_GLOBAL.INIT('INV');
      PRINT_LOG('End Global Intialization for given OU: ' || L_OU ||
                ' and Organization ID: ' || P_ORGANIZATION_ID);
      PRINT_LOG(RPAD(' ', 100, ' '));
      PRINT_LOG(RPAD('*', 100, '*'));
    
      PRINT_LOG(RPAD('*', 100, '*'));
      PRINT_LOG(RPAD(' ', 100, ' '));
    
      /*-- commeted for v 1.6
      FOR I IN (SELECT   XXLOT.INVENTORY_ITEM_ID, MSI.SEGMENT1 ITEM_NAME,
                         XXLOT.ORGANIZATION_ID, XXLOT.SUBINVENTORY_CODE,
                         XXLOT.LOT_NUMBER,
                         SUM (XXLOT.LOT_QUANTITY) LOT_QUANTITY
                    FROM XXMSSL.XXMSSL_LRN_SUBINV_LOT XXLOT,
                         MTL_SYSTEM_ITEMS_B MSI
                   WHERE XXLOT.LRN_NO = P_LRN_NUMBER
                     AND XXLOT.ORGANIZATION_ID = P_ORGANIZATION_ID
                     AND XXLOT.INVENTORY_ITEM_ID = MSI.INVENTORY_ITEM_ID
                     AND XXLOT.ORGANIZATION_ID = MSI.ORGANIZATION_ID
                     AND XXLOT.SUBINVENTORY_CODE = L_TO_SUBINVENTORY
                GROUP BY XXLOT.INVENTORY_ITEM_ID,
                         XXLOT.ORGANIZATION_ID,
                         XXLOT.LOT_NUMBER,
                         XXLOT.SUBINVENTORY_CODE,
                         MSI.SEGMENT1)
      LOOP
         L_COUNT := 0;
         L_AVIL_ONHAND := 0;
         L_HEADER_FLAG := 'S';
         L_ERROR_MESSAGE := NULL;
         PRINT_LOG (
                               'Organization Name: '
                            || L_ORGANIZATION_NAME
                            || ' - Organization_Id: '
                            || I.ORGANIZATION_ID
                            || ' - Item Name: '
                            || I.ITEM_NAME
                            || ' - Inventory_Item_Id: '
                            || I.INVENTORY_ITEM_ID
                            || ' - Lrn_Quantity: '
                            || I.LOT_QUANTITY
                            || ' - Subinventory_Code: '
                            || I.SUBINVENTORY_CODE
                            || ' - l_count: '
                            || L_COUNT
                            || ' - L_Avil_Onhand: '
                            || L_AVIL_ONHAND
                           );
      
         SELECT COUNT (*)
           INTO L_COUNT
           FROM MTL_SYSTEM_ITEMS_B
          WHERE ORGANIZATION_ID = I.ORGANIZATION_ID
            AND INVENTORY_ITEM_ID = I.INVENTORY_ITEM_ID
            AND LOT_CONTROL_CODE = 2;
      
         PRINT_LOG ( 'l_count:- ' || L_COUNT);
      
         IF L_COUNT > 0
         THEN
            L_AVIL_ONHAND :=
               GET_OHQTY (I.INVENTORY_ITEM_ID,
                          I.ORGANIZATION_ID,
                          L_TO_SUBINVENTORY,
                          I.LOT_NUMBER,
                          'ATT'
                         );
         ELSE
            SELECT XXMSSL_WIP_MOVE_ORDER_PKG.GET_ONHAND_QTY
                                                      (I.ORGANIZATION_ID,
                                                       I.INVENTORY_ITEM_ID,
                                                       L_TO_SUBINVENTORY
                                                      )
              INTO L_AVIL_ONHAND
              FROM DUAL;
         END IF;
      
         PRINT_LOG (
                               'System Current On-Hand L_Avil_Onhand:= '
                            || L_AVIL_ONHAND
                            || '    '
                            || '- I.Lot_Quantity:= '
                            || I.LOT_QUANTITY
                           );
         PRINT_LOG ( RPAD ('-', 100, '-'));
         PRINT_LOG ( RPAD (' ', 100, ' '));
      
         IF L_AVIL_ONHAND < I.LOT_QUANTITY
         THEN
            L_HEADER_FLAG := 'E';
            L_ERROR_MESSAGE :=
                  L_ERROR_MESSAGE
               || ' Insufficient lot qty. for item '
               || I.ITEM_NAME;
            PRINT_LOG (
                                  ' Insufficient lot qty. for item '
                               || I.ITEM_NAME
                              );
         ELSE
            PRINT_LOG (
                                  'On-Hand Validation Pass for item '
                               || I.ITEM_NAME
                              );
         END IF;
      
         IF L_HEADER_FLAG = 'E'
         THEN
            FND_FILE.PUT_LINE
               (FND_FILE.LOG,
                   'Calling On-hand Error Procedure: p_pragma_records for item '
                || I.ITEM_NAME
               );
            P_PRAGMA_RECORDS ('HEADER',
                              P_LRN_STATUS,
                              'LRN',
                              P_LRN_NUMBER,
                              P_ORGANIZATION_ID,
                              NULL,
                              NULL,
                              L_ERROR_MESSAGE,
                              G_REQUEST_ID
                             );
            PRINT_LOG (
                               ' Loop Exist for item ' || I.ITEM_NAME
                              );
            EXIT;
         END IF;
      END LOOP;*/
    
      IF L_HEADER_FLAG = 'S' THEN
        PRINT_LOG(RPAD(' ', 100, ' '));
        PRINT_LOG(RPAD('*', 100, '*'));
        PRINT_LOG('Start Processing Records - Cursor C1 For ' ||
                  ' Number: ' || P_LRN_NUMBER);
        PRINT_LOG(RPAD('*', 100, '*'));
        PRINT_LOG(RPAD(' ', 100, ' '));
      
        FOR V1 IN C1 LOOP
          L_RETURN_STATUS            := NULL;
          L_MSG_CNT                  := NULL;
          L_MSG_DATA                 := NULL;
          L_TRANS_COUNT              := NULL;
          L_HEADER_FLAG              := 'S';
          L_ERROR_MESSAGE            := NULL;
          L_TRANSACTION_INTERFACE_ID := NULL;
          L_VAL_FALG                 := 'N';
        
          PRINT_LOG(RPAD('*', 100, '*'));
          PRINT_LOG(RPAD(' ', 100, ' '));
        
          FND_FILE.PUT_LINE(FND_FILE.LOG,
                            'Start Validating On-Hand Qty Records - Cursor For ' ||
                            ' Number: ' || P_LRN_NUMBER || ' item ' ||
                            v1.ITEM_code);
        
          SELECT XXMSSL_WIP_MOVE_ORDER_PKG.GET_ONHAND_QTY(v1.ORGANIZATION_ID,
                                                          v1.INVENTORY_ITEM_ID,
                                                          L_TO_SUBINVENTORY)
            INTO L_AVIL_ONHAND
            FROM DUAL;
        
          PRINT_LOG('l_avil_onhand:- ' || L_AVIL_ONHAND);
        
          /*CHECK ON HAND IS AVAILABLE FOR TRANSACT QTY.*/
          IF L_AVIL_ONHAND < V1.LRN_QUANTITY THEN
            L_VAL_FALG := 'E';
            L_ERROR_MESSAGE  := L_ERROR_MESSAGE ||
                          ' Insufficient ohhand qty. for item ' ||
                          v1.ITEM_code;
            PRINT_LOG('x_message:- ' || L_ERROR_MESSAGE);
            P_PRAGMA_RECORDS('LINE',
                             P_LRN_STATUS,
                             'LRN',
                             P_LRN_NUMBER,
                             P_ORGANIZATION_ID,
                             V1.LINE_NUM,
                             v1.INVENTORY_ITEM_ID,
                             L_ERROR_MESSAGE,
                             G_REQUEST_ID);
          END IF;
        
          PRINT_LOG('end validate onhand quantity');
          PRINT_LOG(RPAD('*', 100, '*'));
          PRINT_LOG(RPAD(' ', 100, ' '));
        
          IF L_VAL_FALG = 'N' THEN
          
          --delete already exsist interface recodrs before insert into interface table V 1.6 
              BEGIN
              DELETE 
              FROM   MTL_TRANSACTION_LOTS_INTERFACE 
              WHERE TRANSACTION_INTERFACE_ID in ( SELECT TRANSACTION_INTERFACE_ID
                                                   FROM   MTL_TRANSACTIONS_INTERFACE  
                                                  WHERE TRANSACTION_REFERENCE = v1.lrn_no
                                                  AND organization_id = v1.organization_id
                                                  AND inventory_item_id =  v1.inventory_item_id
                                                  AND SUBINVENTORY_CODE = L_TO_SUBINVENTORY);
                
               DELETE FROM   MTL_TRANSACTIONS_INTERFACE  
               WHERE TRANSACTION_REFERENCE = v1.lrn_no
               AND organization_id = v1.organization_id
               AND inventory_item_id =  v1.inventory_item_id
               AND SUBINVENTORY_CODE = L_TO_SUBINVENTORY;
               
              EXCEPTION WHEN 
                  OTHERS THEN 
                 PRINT_LOG('error while delete record from interface table '||sqlerrm);
             END ;
             
            
            SELECT MTL_MATERIAL_TRANSACTIONS_S.NEXTVAL
              INTO L_TRANSACTION_INTERFACE_ID
              FROM DUAL;
          
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'Start Inserting Into mtl_transactions_interface Organization Name: ' ||
                              L_ORGANIZATION_NAME || ' - Organization_Id: ' ||
                              V1.ORGANIZATION_ID || ' - Item Name: ' ||
                              V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                              V1.INVENTORY_ITEM_ID || ' - Lrn_Quantity: ' ||
                              V1.LRN_QUANTITY || ' - Subinventory_Code: ' ||
                              V1.SUBINVENTORY_CODE ||
                              ' - l_transaction_interface_id: ' ||
                              L_TRANSACTION_INTERFACE_ID);
          
            BEGIN
              INSERT INTO MTL_TRANSACTIONS_INTERFACE
                (CREATED_BY,
                 CREATION_DATE,
                 INVENTORY_ITEM_ID,
                 LAST_UPDATED_BY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATE_LOGIN,
                 LOCK_FLAG,
                 ORGANIZATION_ID,
                 PROCESS_FLAG,
                 SOURCE_CODE,
                 SOURCE_HEADER_ID,
                 SOURCE_LINE_ID,
                 SUBINVENTORY_CODE,
                 TRANSACTION_DATE,
                 TRANSACTION_HEADER_ID,
                 TRANSACTION_INTERFACE_ID,
                 TRANSACTION_MODE,
                 TRANSACTION_QUANTITY,
                 TRANSACTION_TYPE_ID,
                 TRANSACTION_UOM,
                 TRANSFER_SUBINVENTORY,
                 TRANSACTION_REFERENCE)
              VALUES
                (L_USER_ID,
                 SYSDATE,
                 V1.INVENTORY_ITEM_ID,
                 L_USER_ID,
                 SYSDATE,
                 L_LOGIN_ID,
                 2,
                 P_ORGANIZATION_ID,
                 1,
                 'LRN Subinventory Transfer',
                 1,
                 2,
                 L_TO_SUBINVENTORY,
                 SYSDATE,
                 L_TRANSACTION_INTERFACE_ID,
                 L_TRANSACTION_INTERFACE_ID,
                 3,
                 V1.LRN_QUANTITY,
                 L_TRANSACTION_TYPE_ID,
                 V1.UOM,
                 V1.SUBINVENTORY_CODE,
                 P_LRN_NUMBER);
            EXCEPTION
              WHEN OTHERS THEN
                L_HEADER_FLAG   := 'E';
                L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                   'Error While Insertion the Process Records For - Item Name: ' ||
                                   V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                                   V1.INVENTORY_ITEM_ID ||
                                   ' into Interface Table For Transaction_Interface_Id: ' ||
                                   L_TRANSACTION_INTERFACE_ID;
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While Insertion the Process Records For - Item Name: ' ||
                                  V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                                  V1.INVENTORY_ITEM_ID ||
                                  ' into Interface Table For Transaction_Interface_Id: ' ||
                                  L_TRANSACTION_INTERFACE_ID);
            END;
          
            PRINT_LOG(RPAD(' ', 100, ' '));
          
            BEGIN
              INSERT INTO XXMSSL.XXMSSL_LRN_MTL_TRANS_INTERFACE
                (CREATED_BY,
                 CREATION_DATE,
                 INVENTORY_ITEM_ID,
                 LAST_UPDATED_BY,
                 LAST_UPDATE_DATE,
                 LAST_UPDATE_LOGIN,
                 LOCK_FLAG,
                 ORGANIZATION_ID,
                 PROCESS_FLAG,
                 SOURCE_CODE,
                 SOURCE_HEADER_ID,
                 SOURCE_LINE_ID,
                 SUBINVENTORY_CODE,
                 TRANSACTION_DATE,
                 TRANSACTION_HEADER_ID,
                 TRANSACTION_INTERFACE_ID,
                 TRANSACTION_MODE,
                 TRANSACTION_QUANTITY,
                 TRANSACTION_TYPE_ID,
                 TRANSACTION_UOM,
                 TRANSFER_SUBINVENTORY,
                 TRANSACTION_REFERENCE)
              VALUES
                (L_USER_ID,
                 SYSDATE,
                 V1.INVENTORY_ITEM_ID,
                 L_USER_ID,
                 SYSDATE,
                 L_LOGIN_ID,
                 2,
                 P_ORGANIZATION_ID,
                 1,
                 'LRN Subinventory Transfer',
                 1,
                 2,
                 L_TO_SUBINVENTORY,
                 SYSDATE,
                 L_TRANSACTION_INTERFACE_ID,
                 L_TRANSACTION_INTERFACE_ID,
                 3,
                 V1.LRN_QUANTITY,
                 L_TRANSACTION_TYPE_ID,
                 V1.UOM,
                 V1.SUBINVENTORY_CODE,
                 P_LRN_NUMBER);
            EXCEPTION
              WHEN OTHERS THEN
                L_HEADER_FLAG   := 'E';
                L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                   'Error While Insertion the Process Records For - Item Name: ' ||
                                   V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                                   V1.INVENTORY_ITEM_ID ||
                                   ' into Backup Table:XXMSSL_LRN_MTL_TRANS_INTERFACE For Transaction_Interface_Id: ' ||
                                   L_TRANSACTION_INTERFACE_ID;
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Error While Insertion the Process Records For - Item Name: ' ||
                                  V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                                  V1.INVENTORY_ITEM_ID ||
                                  ' into Backup Table:XXMSSL_LRN_MTL_TRANS_INTERFACE Transaction_Interface_Id: ' ||
                                  L_TRANSACTION_INTERFACE_ID);
            END;
          
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'End Insertion Process Records into Interface Table For Transaction_Interface_Id: ' ||
                              L_TRANSACTION_INTERFACE_ID);
            PRINT_LOG(RPAD(' ', 100, ' '));
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'Start Validating the Item Master Lot Controlled For - Item Name: ' ||
                              V1.ITEM_CODE || ' Item ID: ' ||
                              V1.INVENTORY_ITEM_ID ||
                              ' And Organization_id: ' || P_ORGANIZATION_ID);
          
            SELECT COUNT(1)
              INTO L_COUNT
              FROM MTL_SYSTEM_ITEMS_B
             WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
               AND INVENTORY_ITEM_ID = V1.INVENTORY_ITEM_ID
               AND LOT_CONTROL_CODE = 2;
          
            IF L_COUNT > 0 THEN
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                'Item Master Lot Control Exist L_Count: ' ||
                                L_COUNT || ' For Item ID: ' ||
                                V1.INVENTORY_ITEM_ID ||
                                ' And Organization_id: ' ||
                                P_ORGANIZATION_ID);
              L_REMAINING_QUANTITY := V1.LRN_QUANTITY;
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                ' L_Remaining_Quantity: v1.lrn_quantity: ' ||
                                L_REMAINING_QUANTITY);
              PRINT_LOG(RPAD(' ', 100, ' '));
              PRINT_LOG(RPAD('*', 100, '*'));
              APPS.FND_FILE.PUT_LINE(FND_FILE.LOG,
                                     'Start Fatching Records  - Cursor: C_Lot - Item Lot Control For Line_Num: ' ||
                                     V1.LINE_NUM || ' - Item Name: ' ||
                                     V1.ITEM_CODE ||
                                     ' - Inventory_Item_Id: ' ||
                                     V1.INVENTORY_ITEM_ID ||
                                     ' - L_To_Subinventory: ' ||
                                     L_TO_SUBINVENTORY ||
                                     ' Transaction_Interface_Id: ' ||
                                     L_TRANSACTION_INTERFACE_ID);
              PRINT_LOG(RPAD('*', 100, '*'));
              PRINT_LOG(RPAD(' ', 100, ' '));
            
              --  comment for v1 1.6     
              --FOR V_LOT IN C_LOT (V1.INVENTORY_ITEM_ID,
              --                                L_TO_SUBINVENTORY,
              --                                V1.LINE_NUM
              --                               )
            
              FOR V_LOT IN C_LOT(V1.INVENTORY_ITEM_ID, L_TO_SUBINVENTORY) LOOP
                L_TRANSACTION_QUANTITY := NULL;
                PRINT_LOG('L_Remaining_Quantity: ' || L_REMAINING_QUANTITY);
                PRINT_LOG('Lot Qty: ' || V_LOT.TRANSACTION_QUANTITY);
                PRINT_LOG('Lot No.: ' || V_LOT.LOT_NUMBER);
              
                IF L_REMAINING_QUANTITY <= V_LOT.TRANSACTION_QUANTITY THEN
                  L_TRANSACTION_QUANTITY := L_REMAINING_QUANTITY;
                  L_REMAINING_QUANTITY   := 0;
                ELSIF L_REMAINING_QUANTITY > V_LOT.TRANSACTION_QUANTITY THEN
                  L_TRANSACTION_QUANTITY := V_LOT.TRANSACTION_QUANTITY;
                  L_REMAINING_QUANTITY   := L_REMAINING_QUANTITY -
                                            V_LOT.TRANSACTION_QUANTITY;
                END IF;
              
                PRINT_LOG('L_Remaining_Quantity: ' || L_REMAINING_QUANTITY);
                PRINT_LOG('L_Transaction_Quantity: ' ||
                          L_TRANSACTION_QUANTITY);
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Start Insertion Process Records For L_Transaction_Interface_Id : ' ||
                                  L_TRANSACTION_INTERFACE_ID ||
                                  ' into LOT Interface Table For V_Lot.Lot_Number: ' ||
                                  V_LOT.LOT_NUMBER ||
                                  ' l_transaction_quantity: ' ||
                                  L_TRANSACTION_QUANTITY);
              
                BEGIN
                  INSERT INTO MTL_TRANSACTION_LOTS_INTERFACE
                    (TRANSACTION_INTERFACE_ID,
                     LOT_NUMBER,
                     TRANSACTION_QUANTITY,
                     LAST_UPDATE_DATE,
                     LAST_UPDATED_BY,
                     CREATION_DATE,
                     CREATED_BY)
                  VALUES
                    (L_TRANSACTION_INTERFACE_ID,
                     V_LOT.LOT_NUMBER,
                     L_TRANSACTION_QUANTITY,
                     SYSDATE,
                     L_USER_ID,
                     SYSDATE,
                     L_USER_ID);
                EXCEPTION
                  WHEN OTHERS THEN
                    L_HEADER_FLAG   := 'E';
                    L_ERROR_MESSAGE := L_ERROR_MESSAGE ||
                                       'Error While Insertion the Process Records For 
                               l_transaction_quantity: ' ||
                                       L_TRANSACTION_QUANTITY ||
                                       ' into LOT Interface Table For V_Lot.Lot_Number: ' ||
                                       V_LOT.LOT_NUMBER;
                    FND_FILE.PUT_LINE(FND_FILE.LOG,
                                      'Error While Insertion the Process Records For 
                                  l_transaction_quantity: ' ||
                                      L_TRANSACTION_QUANTITY ||
                                      ' into LOT Interface Table For V_Lot.Lot_Number: ' ||
                                      V_LOT.LOT_NUMBER);
                END;
              
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'END Insertion Process Records For l_transaction_quantity: ' ||
                                  L_TRANSACTION_QUANTITY ||
                                  ' into LOT Interface Table For V_LOT.LOT_NUMBER: ' ||
                                  V_LOT.LOT_NUMBER);
              
                IF L_REMAINING_QUANTITY = 0 THEN
                  EXIT;
                END IF;
              END LOOP;
            END IF;
          
            PRINT_LOG(RPAD(' ', 100, ' '));
            PRINT_LOG(RPAD('-', 100, '-'));
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'Calling API Process:Inv_Txn_Manager_Pub.Process_Transactions For P_LRN_NUMBER: ' ||
                              P_LRN_NUMBER ||
                              'And l_transaction_interface_id: ' ||
                              L_TRANSACTION_INTERFACE_ID);
            PRINT_LOG(RPAD('-', 100, '-'));
            PRINT_LOG(RPAD(' ', 100, ' '));
            V_RET_VAL := INV_TXN_MANAGER_PUB.PROCESS_TRANSACTIONS(P_API_VERSION      => 1.0,
                                                                  P_INIT_MSG_LIST    => FND_API.G_TRUE,
                                                                  P_COMMIT           => FND_API.G_TRUE,
                                                                  P_VALIDATION_LEVEL => FND_API.G_VALID_LEVEL_FULL,
                                                                  X_RETURN_STATUS    => L_RETURN_STATUS,
                                                                  X_MSG_COUNT        => L_MSG_CNT,
                                                                  X_MSG_DATA         => L_MSG_DATA,
                                                                  X_TRANS_COUNT      => L_TRANS_COUNT,
                                                                  P_TABLE            => 1,
                                                                  P_HEADER_ID        => L_TRANSACTION_INTERFACE_ID);
            FND_FILE.PUT_LINE(FND_FILE.LOG,
                              'End API Process:Inv_Txn_Manager_Pub.Process_Transactions For P_LRN_NUMBER: ' ||
                              P_LRN_NUMBER ||
                              ' And l_transaction_interface_id: ' ||
                              L_TRANSACTION_INTERFACE_ID);
            PRINT_LOG('API Return Status: ' || L_RETURN_STATUS);
            PRINT_LOG('API Message Cnt: ' || NVL(L_MSG_CNT, 0));
            PRINT_LOG(RPAD(' ', 100, ' '));
          
            IF (NVL(L_RETURN_STATUS, 'E') <> 'S') THEN
              L_MSG_CNT := NVL(L_MSG_CNT, 0) + 1;
            
              FOR I IN 1 .. L_MSG_CNT LOOP
                FND_MSG_PUB.GET(P_MSG_INDEX     => I,
                                P_ENCODED       => 'F',
                                P_DATA          => L_MSG_DATA,
                                P_MSG_INDEX_OUT => X_MSG_INDEX);
                X_MSG := X_MSG || '.' || L_MSG_DATA;
              END LOOP;
            
              BEGIN
                SELECT ERROR_CODE || ':- ' || ERROR_EXPLANATION
                  INTO L_INTERFACE_ERROR
                  FROM MTL_TRANSACTIONS_INTERFACE
                 WHERE TRANSACTION_INTERFACE_ID =
                       L_TRANSACTION_INTERFACE_ID
                   AND SOURCE_CODE = 'LRN Subinventory Transfer';
              EXCEPTION
                WHEN OTHERS THEN
                  L_INTERFACE_ERROR := NULL;
              END;
            
              ERRBUF := X_MSG || 'Error while rejection:- Interface Error:' ||
                        L_INTERFACE_ERROR;
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                'API Error in Subinventory Transfer For P_LRN_NUMBER: ' ||
                                P_LRN_NUMBER ||
                                ' And  Transaction_Interface_Id:- ' ||
                                L_TRANSACTION_INTERFACE_ID ||
                                'API Error Message: ' || L_INTERFACE_ERROR);
              L_ERROR_MESSAGE := SUBSTR(L_INTERFACE_ERROR, 1, 2000);
            
              L_ERROR_MESSAGE := 'Error in Reject Subinventory Transfer:' ||
                                 X_MSG;
            
              BEGIN
                L_HEADER_FLAG := 'E';
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'Calling API Error Procedure: p_pragma_records For l_transaction_interface_id: ' ||
                                  L_TRANSACTION_INTERFACE_ID);
              
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'p_lrn_status: ' || P_LRN_STATUS);
              
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'p_lrn_number: ' || P_LRN_NUMBER);
              
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'v1.line_num: ' || V1.LINE_NUM);
              
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'l_interface_error: ' ||
                                  L_INTERFACE_ERROR);
              
                FND_FILE.PUT_LINE(FND_FILE.LOG,
                                  'g_request_id: ' || G_REQUEST_ID);
                P_PRAGMA_RECORDS('LINE',
                                 P_LRN_STATUS,
                                 'LRN',
                                 P_LRN_NUMBER,
                                 P_ORGANIZATION_ID,
                                 V1.LINE_NUM,
                                 NULL,
                                 L_INTERFACE_ERROR,
                                 G_REQUEST_ID);
              EXCEPTION
                WHEN OTHERS THEN
                  FND_FILE.PUT_LINE(FND_FILE.LOG,
                                    'Error While Update the API Error Message In Staging 
                         table xxmssl_lrn_detail_t for l_transaction_interface_id ' ||
                                    L_TRANSACTION_INTERFACE_ID || '  No.: ' ||
                                    P_LRN_NUMBER || ' and  Line Num: ' ||
                                    V1.LINE_NUM);
              END;
            ELSIF NVL(L_RETURN_STATUS, 'E') = 'S' THEN
              ERRBUF := NULL;
              FND_FILE.PUT_LINE(FND_FILE.LOG,
                                'Reject Sub-Inventory Transfer Successfully Complete For l_transaction_interface_id ' ||
                                L_TRANSACTION_INTERFACE_ID || '  No: ' ||
                                P_LRN_NUMBER || '- Line_Num: ' ||
                                V1.LINE_NUM || ' - Item Name: ' ||
                                V1.ITEM_CODE || ' - Inventory_Item_Id: ' ||
                                V1.INVENTORY_ITEM_ID);
              PRINT_LOG(RPAD('-', 100, '-'));
              PRINT_LOG(RPAD(' ', 100, ' '));
            
              BEGIN
                UPDATE XXMSSL.XXMSSL_LRN_DETAIL_T
                   SET SUBINVENTORY_TRANSFER = 'R',
                       REQUEST_ID            = G_REQUEST_ID
                 WHERE ORGANIZATION_ID = P_ORGANIZATION_ID
                   AND LRN_NO = P_LRN_NUMBER
                   AND LINE_NUM = V1.LINE_NUM;
              EXCEPTION
                WHEN OTHERS THEN
                  FND_FILE.PUT_LINE(FND_FILE.LOG,
                                    'Error While updating the Success Flag in staging table XXMSSL_LRN_DETAIL_T For l_transaction_interface_id ' ||
                                    L_TRANSACTION_INTERFACE_ID || '  No: ' ||
                                    P_LRN_NUMBER || ' and Line No: ' ||
                                    V1.LINE_NUM);
              END;
            
              IF L_HEADER_FLAG = 'E' THEN
                EXIT;
              END IF;
            END IF;
          
            PRINT_LOG(RPAD('-', 100, '-'));
            PRINT_LOG(RPAD(' ', 100, ' '));
          END IF;
        END LOOP;
      
        PRINT_LOG('L_HEADER_FLAG: ' || L_HEADER_FLAG);
      
        IF L_HEADER_FLAG = 'E' THEN
        
          ROLLBACK;
          PRINT_LOG('ROLLBACK: ' || L_HEADER_FLAG);
        
        ELSIF L_HEADER_FLAG = 'S' THEN
        
          COMMIT;
          PRINT_LOG('COMMIT: ' || L_HEADER_FLAG);
        
        END IF;
      END IF;
    END IF;
  
    P_GENERATE_OUTPUT(P_LRN_NUMBER,
                      P_LRN_STATUS,
                      P_LRN_ACTION_TYPE,
                      P_ORGANIZATION_ID,
                      L_ORGANIZATION_NAME,
                      L_TO_SUBINVENTORY,
                      G_REQUEST_ID);
  EXCEPTION
    WHEN OTHERS THEN
      ERRBUF := 'EXCEPTION IN LRN_REJECT_SUBINVENTORY_TFR:' || SQLERRM;
      PRINT_LOG('EXCEPTION IN LRN_REJECT_SUBINVENTORY_TFR:' || SQLERRM);
  END LRN_REJECT_SUBINVENTORY_TFR;

  FUNCTION GET_ADDRESS(ADDR_LIST IN OUT VARCHAR2) RETURN VARCHAR2 IS
    ADDR VARCHAR2(256);
    I    PLS_INTEGER;
  
    FUNCTION LOOKUP_UNQUOTED_CHAR(STR IN VARCHAR2, CHRS IN VARCHAR2)
      RETURN PLS_INTEGER AS
      C            VARCHAR2(5);
      I            PLS_INTEGER;
      LEN          PLS_INTEGER;
      INSIDE_QUOTE BOOLEAN;
    BEGIN
      INSIDE_QUOTE := FALSE;
      I            := 1;
      LEN          := LENGTH(STR);
    
      WHILE (I <= LEN) LOOP
        C := SUBSTR(STR, I, 1);
      
        IF (INSIDE_QUOTE) THEN
          IF (C = '"') THEN
            INSIDE_QUOTE := FALSE;
          ELSIF (C = '\') THEN
            I := I + 1; -- SKIP THE QUOTE CHARACTER
          END IF;
        END IF;
      
        IF (C = '"') THEN
          INSIDE_QUOTE := TRUE;
        END IF;
      
        IF (INSTR(CHRS, C) >= 1) THEN
          RETURN I;
        END IF;
      
        I := I + 1;
      END LOOP;
    
      RETURN 0;
    END;
  BEGIN
    ADDR_LIST := LTRIM(ADDR_LIST);
    I         := LOOKUP_UNQUOTED_CHAR(ADDR_LIST, ',;');
  
    IF (I >= 1) THEN
      ADDR      := SUBSTR(ADDR_LIST, 1, I - 1);
      ADDR_LIST := SUBSTR(ADDR_LIST, I + 1);
    ELSE
      ADDR      := ADDR_LIST;
      ADDR_LIST := '';
    END IF;
  
    I := LOOKUP_UNQUOTED_CHAR(ADDR, '<');
  
    IF (I >= 1) THEN
      ADDR := SUBSTR(ADDR, I + 1);
      I    := INSTR(ADDR, '>');
    
      IF (I >= 1) THEN
        ADDR := SUBSTR(ADDR, 1, I - 1);
      END IF;
    END IF;
  
    RETURN ADDR;
  END;
  /**********************************************************************************************************
  REM COPYRIGHT (C) 2025 MOTHERSON ALL RIGHTS RESERVED.
  REM *******************************************************************************************************
  REM FILE NAME                : XXMSSL_LRN_PKG.P_MAIL_ATTACHMENT
  REM DOC REF(S)               : REFER OLD PACKAGE XXMSSL_LRN_PKG
  REM PROJECT                  : MOTHERSON PROJECT
  REM DESCRIPTION              : LRN/MRN EMAIL NOTIFICATION WITH PROCESS RECORDS ATTACHMENT  
  REM                            WHILE APPROVE, REJECT, RETURN TO CREATOR AND COMPELETE,AUTHOR: RAVISH CHAUHAN
  REM
  REM CHANGE HISTORY INFORMATION
  REM --------------------------
  REM VERSION  DATE         AUTHOR           CHANGE REFERENCE / DESCRIPTION
  REM -------  -----------  ---------------  ----------------------------------------
  REM 1.0     07-JAN-2025     VIKAS CHAUHAN   INITIAL VERSION
  REM *******************************************************************************************************/
  PROCEDURE P_MAIL_ATTACHMENT(P_TO          IN VARCHAR2,
                              P_CC          IN VARCHAR2 DEFAULT NULL,
                              P_BCC         IN VARCHAR2 DEFAULT NULL,
                              P_FROM        IN VARCHAR2,
                              P_SUBJECT     IN VARCHAR2,
                              P_TEXT_MSG    IN VARCHAR2 DEFAULT NULL,
                              P_ATTACH_NAME IN VARCHAR2 DEFAULT NULL,
                              P_ATTACH_MIME IN VARCHAR2 DEFAULT NULL,
                              P_SMTP_HOST   IN VARCHAR2,
                              P_SMTP_PORT   IN NUMBER DEFAULT 25,
                              P_SQL         IN VARCHAR2) AS
    L_MAIL_CONN UTL_SMTP.CONNECTION;
    L_BOUNDARY  VARCHAR2(50) := '----=*#abc1234321cba#*=';
    C           NUMBER;
    D           NUMBER;
    COL_CNT     INTEGER;
    REC_TAB     DBMS_SQL.DESC_TAB;
    ACLOB       CLOB;
    J           NUMBER;
    ASTR        VARCHAR2(10000);
    NAMEVAR     VARCHAR2(500);
    NUMVAR      NUMBER;
    L_AMOUNT    BINARY_INTEGER := 1440;
    L_LENGTH    NUMBER;
    L_STEPS     NUMBER;
    ARAW        RAW(32767);
    LV_TO       VARCHAR2(4000);
    LV_CC       VARCHAR2(4000);
  BEGIN
    BEGIN
      C := DBMS_SQL.OPEN_CURSOR;
      DBMS_LOB.CREATETEMPORARY(ACLOB, TRUE, DBMS_LOB.SESSION);
      DBMS_SQL.PARSE(C, P_SQL, DBMS_SQL.NATIVE);
      D := DBMS_SQL.EXECUTE(C);
      DBMS_SQL.DESCRIBE_COLUMNS(C, COL_CNT, REC_TAB);
    
      -- DEFINE COLUMNS
      FOR J IN 1 .. COL_CNT LOOP
        IF REC_TAB(J).COL_TYPE = 2 THEN
          DBMS_SQL.DEFINE_COLUMN(C, J, NUMVAR);
        ELSE
          DBMS_SQL.DEFINE_COLUMN(C, J, NAMEVAR, 32000);
        END IF;
      END LOOP;
    
      L_MAIL_CONN := UTL_SMTP.OPEN_CONNECTION(P_SMTP_HOST, P_SMTP_PORT);
      UTL_SMTP.HELO(L_MAIL_CONN, P_SMTP_HOST);
      UTL_SMTP.MAIL(L_MAIL_CONN, P_FROM);
      LV_TO := REPLACE(P_TO, ',', ';');
      LV_CC := REPLACE(P_CC, ',', ';');
    
      WHILE (LV_TO IS NOT NULL) LOOP
        UTL_SMTP.RCPT(L_MAIL_CONN, APPS.XXMSSL_LRN_PKG.GET_ADDRESS(LV_TO));
      END LOOP;
    
      WHILE (LV_CC IS NOT NULL) LOOP
        UTL_SMTP.RCPT(L_MAIL_CONN, APPS.XXMSSL_LRN_PKG.GET_ADDRESS(LV_CC));
      END LOOP;
    
      UTL_SMTP.OPEN_DATA(L_MAIL_CONN);
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                          'Date: ' ||
                          TO_CHAR(SYSDATE, 'Dy, DD Mon YYYY HH24:MI:SS') || --TO_CHAR (SYSDATE, 'DD-MON-YYYY HH24:MI:SS') || ' ' ||
                          '+0530' || UTL_TCP.CRLF);
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                          'To: ' || REPLACE(P_TO, ',', ';') || UTL_TCP.CRLF);
    
      IF TRIM(P_CC) IS NOT NULL THEN
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                            'CC: ' || REPLACE(P_CC, ',', ';') ||
                            UTL_TCP.CRLF); --REPLACE (P_CC, ',', ';')
      END IF;
    
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN, 'From: ' || P_FROM || UTL_TCP.CRLF);
      UTL_SMTP.WRITE_RAW_DATA(L_MAIL_CONN,
                              UTL_RAW.CAST_TO_RAW('Subject: ' || P_SUBJECT ||
                                                  UTL_TCP.CRLF));
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                          'Reply-To: ' || P_FROM || UTL_TCP.CRLF);
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN, 'MIME-Version: 1.0' || UTL_TCP.CRLF);
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                          'Content-Type: multipart/mixed; charset=windows-1251; boundary="' ||
                          L_BOUNDARY || '"' || UTL_TCP.CRLF || UTL_TCP.CRLF);
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                          'Content-Transfer-Encoding: 8bit' || UTL_TCP.CRLF ||
                          UTL_TCP.CRLF);
    
      IF P_TEXT_MSG IS NOT NULL THEN
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                            '--' || L_BOUNDARY || UTL_TCP.CRLF);
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                            'Content-Type: text/html; charset=windows-1251' ||
                            UTL_TCP.CRLF || UTL_TCP.CRLF);
        UTL_SMTP.WRITE_RAW_DATA(L_MAIL_CONN,
                                UTL_RAW.CAST_TO_RAW(P_TEXT_MSG ||
                                                    UTL_TCP.CRLF));
      END IF;
    
      IF P_ATTACH_NAME IS NOT NULL THEN
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                            '--' || L_BOUNDARY || UTL_TCP.CRLF);
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                            'Content-Type: ' || P_ATTACH_MIME || '; name="' ||
                            P_ATTACH_NAME || '"' || UTL_TCP.CRLF);
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                            'Content-Transfer-Encoding: base64' ||
                            UTL_TCP.CRLF);
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                            'Content-Disposition: attachment; filename="' ||
                            P_ATTACH_NAME || '"' || UTL_TCP.CRLF ||
                            UTL_TCP.CRLF);
        --WRITE HEADER
        DBMS_LOB.APPEND(ACLOB, 'sep=,' || CHR(13) || CHR(10));
        ASTR := '';
      
        FOR J IN 1 .. COL_CNT LOOP
          IF J <> COL_CNT THEN
            ASTR := ASTR || REC_TAB(J).COL_NAME || CHR(44);
          ELSE
            ASTR := ASTR || REC_TAB(J).COL_NAME || CHR(13) || CHR(10);
          END IF;
        END LOOP;
      
        DBMS_LOB.APPEND(ACLOB, ASTR);
      
        WHILE DBMS_SQL.FETCH_ROWS(C) > 0 LOOP
          ASTR := '';
        
          FOR J IN 1 .. COL_CNT LOOP
            IF (REC_TAB(J).COL_TYPE = 2) THEN
              DBMS_SQL.COLUMN_VALUE(C, J, NUMVAR);
            
              IF J <> COL_CNT THEN
                ASTR := ASTR || NUMVAR || CHR(44);
              ELSE
                /*LAST COL*/
                ASTR := ASTR || NUMVAR || CHR(13) || CHR(10);
              END IF;
            ELSE
              DBMS_SQL.COLUMN_VALUE(C, J, NAMEVAR);
            
              IF J <> COL_CNT THEN
                ASTR := ASTR
                       --  || '="'
                        ||
                        REPLACE(REPLACE(REPLACE(REPLACE(NAMEVAR, ',', ' '),
                                                '"',
                                                ' '),
                                        CHR(13),
                                        ''),
                                CHR(10),
                                ' ')
                       --  || '"'
                        || CHR(44);
              ELSE
                /*LAST COL*/
                ASTR := ASTR
                       -- || '="'
                        ||
                        REPLACE(REPLACE(REPLACE(REPLACE(NAMEVAR, ',', ' '),
                                                '"',
                                                ' '),
                                        CHR(13),
                                        ''),
                                CHR(10),
                                ' ')
                       --    || '"'
                        || CHR(13) || CHR(10);
              END IF;
            END IF;
          END LOOP;
        
          DBMS_LOB.APPEND(ACLOB, ASTR);
        END LOOP;
      
        L_LENGTH := DBMS_LOB.GETLENGTH(ACLOB);
        L_STEPS  := FLOOR(L_LENGTH / L_AMOUNT) + 1;
      
        FOR J IN 0 .. L_STEPS LOOP
          ASTR := DBMS_LOB.SUBSTR(ACLOB, L_AMOUNT, (J * L_AMOUNT) + 1);
        
          IF ASTR IS NOT NULL THEN
            ARAW := UTL_RAW.CAST_TO_RAW(ASTR);
            ASTR := UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(ARAW));
            UTL_SMTP.WRITE_DATA(L_MAIL_CONN, ASTR);
          END IF;
        END LOOP;
      
        UTL_SMTP.WRITE_DATA(L_MAIL_CONN, UTL_TCP.CRLF || UTL_TCP.CRLF);
      END IF;
    
      UTL_SMTP.WRITE_DATA(L_MAIL_CONN,
                          '--' || L_BOUNDARY || '--' || UTL_TCP.CRLF);
      UTL_SMTP.CLOSE_DATA(L_MAIL_CONN);
      UTL_SMTP.QUIT(L_MAIL_CONN);
    EXCEPTION
      WHEN OTHERS THEN
        IF DBMS_SQL.IS_OPEN(C) THEN
          DBMS_SQL.CLOSE_CURSOR(C);
        END IF;
      
        DBMS_OUTPUT.PUT_LINE('error in main ' || SQLERRM ||
                             DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());
        DBMS_LOB.FREETEMPORARY(ACLOB);
        UTL_SMTP.CLOSE_DATA(L_MAIL_CONN);
        UTL_SMTP.QUIT(L_MAIL_CONN);
        RAISE;
    END;
  END;
  /**********************************************************************************************************
  REM COPYRIGHT (C) 2025 MOTHERSON ALL RIGHTS RESERVED.
  REM *******************************************************************************************************
  REM FILE NAME                : XXMSSL_LRN_PKG.P_EMAIL_NOTIF
  REM DOC REF(S)               : REFER OLD PACKAGE XXMSSL_LRN_PKG
  REM PROJECT                  : MOTHERSON PROJECT
  REM DESCRIPTION              : LRN/MRN EMAIL NOTIFICATION WHILE APPROVE, REJECT, RETURN TO CREATOR AND COMPELETE,
  REM                               AUTHOR: RAVISH CHAUHAN
  REM
  REM CHANGE HISTORY INFORMATION
  REM --------------------------
  REM VERSION  DATE         AUTHOR           CHANGE REFERENCE / DESCRIPTION
  REM -------  -----------  ---------------  ----------------------------------------
  REM 1.0     07-JAN-2025     VIKAS CHAUHAN   INITIAL VERSION
  REM *******************************************************************************************************/
   PROCEDURE P_EMAIL_NOTIF (
      P_ACTION_USER       NUMBER,
      P_LRN_MRN_STATUS    VARCHAR2,
      P_LRN_MRN_TYPE      VARCHAR2,
      P_LRN_MRN_NUM       VARCHAR2,
      P_MAIL_TYPE         VARCHAR2,
      P_ORGANIZATION_ID   NUMBER,
      P_REQUEST_ID        NUMBER
   )
   IS
      ERRBUF                VARCHAR2 (2000);
      RETCODE               VARCHAR2 (2000);
      LV_MAIL_TO            VARCHAR2 (4000);
      LV_MAIL_CC            VARCHAR2 (4000);
      LV_MAIL_CC1           VARCHAR2 (4000);
      LV_MAIL_CC2           VARCHAR2 (4000);
      LV_ADD_RECIPT_CC      VARCHAR2 (4000);
      MAILHOST              VARCHAR2 (30)    := fnd_profile.VALUE ('XXMSSL_MAIL_HOST');
      SENDER                VARCHAR2 (2000)
                                := FND_PROFILE.VALUE ('XXMSSL FROM MAIL OCS');
      LV_FILE_NAME          VARCHAR2 (200);
      LV_ORG_CODE           VARCHAR2 (5);
      LV_QUERY              VARCHAR2 (5000);
      LV_MAIL_FLAG          VARCHAR2 (1)     := 'N';
      L_DATA_TYPE           VARCHAR2 (100);
      L_SUBJECT             VARCHAR2 (1000);
      L_BODY                VARCHAR2 (2000);
      L_BODY_LINE_2         VARCHAR2 (2000);
      L_BODY_LINE_3         VARCHAR2 (2000);
      L_SYS_DATE            VARCHAR2 (100);
      V_MAIL                VARCHAR2 (32000);
      V_TO_MAIL             VARCHAR2 (32000);
      V_CC_MAIL             VARCHAR2 (32000);
      L_CREATOR             VARCHAR2(240);
      L_APPROVER            VARCHAR2(240);
      L_ORGANIZATION_CODE   VARCHAR2 (30);
      L_MAIL_TYPE  VARCHAR2 (30);
   BEGIN
      L_DATA_TYPE := NULL;
      LV_QUERY := NULL;
      L_SUBJECT := NULL;
      L_SYS_DATE := TO_CHAR (SYSDATE, 'DD-MON-YYYY');
      V_TO_MAIL := NULL;
      V_CC_MAIL := NULL;
      LV_MAIL_CC1 := NULL;
      LV_MAIL_CC2 := NULL;
      LV_ADD_RECIPT_CC := NULL;
      L_CREATOR := NULL;
      L_APPROVER := NULL;
      L_BODY := NULL;
      L_BODY_LINE_2 := NULL;
      L_BODY_LINE_3 := NULL;
      L_ORGANIZATION_CODE := NULL;
      L_MAIL_TYPE := NULL;
      V_CC_MAIL := NULL;
      G_DEBUG_FLAG := 'Y';
      
      
      PRINT_LOG ( RPAD ('*', 100, '*'));
      FND_FILE.PUT_LINE (1, 'Start Email Notification Process');
      PRINT_LOG ( RPAD ('*', 100, '*'));
      PRINT_LOG ( RPAD (' ', 100, ' '));
     APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                      'EMAIL Notification',
      P_LRN_MRN_NUM,  'p_action_user: ' || P_ACTION_USER);
     APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                      'EMAIL Notification',
      P_LRN_MRN_NUM,     'p_lrn_mrn_status: '
                         || P_LRN_MRN_STATUS
                         || ' p_lrn_mrn_type: '
                         || P_LRN_MRN_TYPE
                        );
     APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                      'EMAIL Notification',
      P_LRN_MRN_NUM,  'p_lrn_mrn_num: ' || P_LRN_MRN_NUM);
   APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                      'EMAIL Notification',
      P_LRN_MRN_NUM,  'p_mail_type: ' || P_MAIL_TYPE);
    APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                      'EMAIL Notification',
      P_LRN_MRN_NUM, 
                         'Organization ID: ' || P_ORGANIZATION_ID
                        );   

      BEGIN
         SELECT ORGANIZATION_CODE
           INTO L_ORGANIZATION_CODE
           FROM ORG_ORGANIZATION_DEFINITIONS
          WHERE ORGANIZATION_ID = P_ORGANIZATION_ID;
      EXCEPTION
         WHEN OTHERS
         THEN
            L_ORGANIZATION_CODE := NULL;
      END;
      
   APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                      'EMAIL Notification',
      P_LRN_MRN_NUM,  'l_organization_code: ' || L_ORGANIZATION_CODE ); 
      
      BEGIN
      SELECT LRN_STATUS INTO L_MAIL_TYPE
      FROM XXMSSL_LRN_HEADER_T
      WHERE LRN_NO = P_LRN_MRN_NUM
      AND ORGANIZATION_ID = P_ORGANIZATION_ID;
      EXCEPTION WHEN OTHERS
      THEN 
      L_MAIL_TYPE := NULL;
      END;

      APPS.XXMSSL_LRN_PKG.PRINT_LOG  ( 'EMAIL Notification',
      P_LRN_MRN_NUM,'p_mail_type: '||P_MAIL_TYPE||'  l_mail_type: ' || L_MAIL_TYPE
                        ); 


      IF P_MAIL_TYPE = 'APPROVE' AND L_MAIL_TYPE = 'APPROVE'
      THEN
         BEGIN
           SELECT LISTAGG(TO_MAIL, ',') WITHIN GROUP(ORDER BY TO_MAIL) EMAIL INTO V_TO_MAIL
             FROM (SELECT DISTINCT RTRIM (LTRIM (ATTRIBUTE1)) TO_MAIL
              FROM FND_LOOKUP_VALUES
                   WHERE LOOKUP_TYPE = 'XXMSSL_INVENTORY_EMAIL_MASTER'
                   AND DESCRIPTION = 'LRN|QA'
                   AND ENABLED_FLAG = 'Y'
                   AND END_DATE_ACTIVE IS NULL
                   AND ATTRIBUTE_CATEGORY = 'EMAIL'
                   AND UPPER(TAG) = UPPER(L_ORGANIZATION_CODE));
            EXCEPTION WHEN OTHERS THEN
                     V_TO_MAIL:= NULL;
                END;
                
                APPS.XXMSSL_LRN_PKG.PRINT_LOG  ('EMAIL Notification',
      P_LRN_MRN_NUM,'V_TO_MAIL: ' || V_TO_MAIL
                        );       
                
      /* BEGIN
           SELECT LISTAGG(TO_MAIL, ',') WITHIN GROUP(ORDER BY TO_MAIL) EMAIL INTO LV_ADD_RECIPT_CC
             FROM (SELECT DISTINCT RTRIM (LTRIM (ATTRIBUTE1)) TO_MAIL
              FROM FND_LOOKUP_VALUES
                   WHERE LOOKUP_TYPE = 'XXMSSL_INVENTORY_EMAIL_MASTER'
                   AND DESCRIPTION = 'LRN|CC'
                   AND ENABLED_FLAG = 'Y'
                   AND END_DATE_ACTIVE IS NULL
                   AND ATTRIBUTE_CATEGORY = 'EMAIL'
                   AND UPPER(TAG) = UPPER(L_ORGANIZATION_CODE));
            EXCEPTION WHEN OTHERS THEN
                     LV_ADD_RECIPT_CC:= NULL;
                END; PRINT_LOG (
                         'lv_add_recipt_cc: ' || LV_ADD_RECIPT_CC
                        );     */
                        
    
                    
         BEGIN
         SELECT LISTAGG(TO_MAIL, ',') WITHIN GROUP(ORDER BY TO_MAIL) EMAIL INTO LV_MAIL_CC1
           FROM (SELECT PAPF.EMAIL_ADDRESS TO_MAIL
              FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                   APPS.FND_USER FU,
                   APPS.PER_ALL_PEOPLE_F PAPF
             WHERE -1 = -1
               AND FU.USER_ID = G_USER_ID--P_ACTION_USER
               AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
               AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                       AND PAPF.EFFECTIVE_END_DATE
               AND ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_MRN_NUM
               union all
               SELECT DISTINCT RTRIM (LTRIM (ATTRIBUTE1)) TO_MAIL
              FROM FND_LOOKUP_VALUES
                   WHERE LOOKUP_TYPE = 'XXMSSL_INVENTORY_EMAIL_MASTER'
                   AND DESCRIPTION = 'LRN|CC'
                   AND ENABLED_FLAG = 'Y'
                   AND END_DATE_ACTIVE IS NULL
                   AND ATTRIBUTE_CATEGORY = 'EMAIL'
                   AND UPPER(TAG) = UPPER(L_ORGANIZATION_CODE)
                   );
         EXCEPTION
            WHEN OTHERS
            THEN
               L_APPROVER := NULL;
               LV_MAIL_CC1 :=NULL;
         END;
         
         
             APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,'lv_mail_cc1: ' || LV_MAIL_CC1
                        );
        

         IF V_TO_MAIL IS NOT NULL
         THEN
            BEGIN
               SELECT PAPF.FULL_NAME,
                      PAPF.EMAIL_ADDRESS EMAIL_ADD
                 INTO L_CREATOR,
                      LV_MAIL_CC2
                 FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                      APPS.FND_USER FU,
                      APPS.PER_ALL_PEOPLE_F PAPF
                WHERE -1 = -1
                  AND FU.USER_ID = XXH.CREATED_BY
                  AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
                  AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                          AND PAPF.EFFECTIVE_END_DATE
                  AND ORGANIZATION_ID = P_ORGANIZATION_ID
                  AND LRN_NO = P_LRN_MRN_NUM;
            EXCEPTION
               WHEN OTHERS
               THEN
                  L_CREATOR := NULL;
                  LV_MAIL_CC2 := NULL;
            END;
            
                      APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                        'EMAIL Notification',
      P_LRN_MRN_NUM, 'lv_mail_cc2: ' || LV_MAIL_CC2
                        );

         ELSE
            BEGIN
               SELECT PAPF.FULL_NAME,
                      PAPF.EMAIL_ADDRESS EMAIL_ADD
               INTO   L_CREATOR,
                      V_TO_MAIL
                 FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                      APPS.FND_USER FU,
                      APPS.PER_ALL_PEOPLE_F PAPF
                WHERE -1 = -1
                  AND FU.USER_ID = XXH.CREATED_BY
                  AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
                  AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                          AND PAPF.EFFECTIVE_END_DATE
                  AND ORGANIZATION_ID = P_ORGANIZATION_ID
                  AND LRN_NO = P_LRN_MRN_NUM;
            EXCEPTION
               WHEN OTHERS
               THEN
                  L_CREATOR := NULL;
                  V_TO_MAIL := NULL;
            END;
            
                     APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                      'EMAIL Notification',
      P_LRN_MRN_NUM,   'v_to_mail: ' || V_TO_MAIL
                        );
         END IF;

         L_SUBJECT :=
               'Request '
            || P_LRN_MRN_TYPE
            || ' No- '
            || P_LRN_MRN_NUM
            || ' has been approved.';
         L_BODY :=
               'This is to inform you that Request '
            || P_LRN_MRN_TYPE
            || ' No.- '
            || P_LRN_MRN_NUM
            || ' has been accepted by Approver.';
        L_BODY_LINE_2 :=    'This is Test Email. In case of any query or clarification, kindly mail at ' || LV_MAIL_CC1 || ' .';
         L_BODY_LINE_3 :=
            'Note : This communication is system generated and please do not reply to this email. If you are not the correct recipient for this notification, please contact to Administrator.';
         LV_FILE_NAME := P_LRN_MRN_TYPE || '_' || P_LRN_MRN_NUM || '_FILE.xls';
         APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,'L_SUBJECT: ' || L_SUBJECT
                        );
         
         
      END IF;
      
       IF P_MAIL_TYPE = 'REJECT' AND L_MAIL_TYPE = 'REJECT'
      THEN
      
           BEGIN
               SELECT PAPF.EMAIL_ADDRESS EMAIL_ADD
                 INTO V_TO_MAIL
                 FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                      APPS.FND_USER FU,
                      APPS.PER_ALL_PEOPLE_F PAPF
                WHERE -1 = -1
                  AND FU.USER_ID = XXH.CREATED_BY
                  AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
                  AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                          AND PAPF.EFFECTIVE_END_DATE
                  AND ORGANIZATION_ID = P_ORGANIZATION_ID
                  AND LRN_NO = P_LRN_MRN_NUM;
            EXCEPTION
               WHEN OTHERS
               THEN
                 V_TO_MAIL := NULL;
            END;
            

            
           BEGIN
           SELECT LISTAGG(TO_MAIL, ',') WITHIN GROUP(ORDER BY TO_MAIL) EMAIL INTO LV_ADD_RECIPT_CC
             FROM (SELECT DISTINCT RTRIM (LTRIM (ATTRIBUTE1)) TO_MAIL
              FROM FND_LOOKUP_VALUES
                   WHERE LOOKUP_TYPE = 'XXMSSL_INVENTORY_EMAIL_MASTER'
                   AND DESCRIPTION = 'LRN|CC'
                   AND ENABLED_FLAG = 'Y'
                   AND END_DATE_ACTIVE IS NULL
                   AND ATTRIBUTE_CATEGORY = 'EMAIL'
                   AND UPPER(TAG) = UPPER(L_ORGANIZATION_CODE));
                 EXCEPTION WHEN OTHERS THEN
                     LV_ADD_RECIPT_CC:= NULL;
             END;
                
                
         BEGIN
            SELECT PAPF.FULL_NAME,
                   PAPF.EMAIL_ADDRESS EMAIL_ADD
              INTO L_APPROVER,
                   LV_MAIL_CC1
              FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                   APPS.FND_USER FU,
                   APPS.PER_ALL_PEOPLE_F PAPF
             WHERE -1 = -1
               AND FU.USER_ID = P_ACTION_USER
               AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
               AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                       AND PAPF.EFFECTIVE_END_DATE
               AND ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO = P_LRN_MRN_NUM;
         EXCEPTION
            WHEN OTHERS
            THEN
               L_APPROVER := NULL;
               LV_MAIL_CC1 := NULL;
         END;
         
              APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,
                         'V_TO_MAIL: '||V_TO_MAIL||'  lv_add_recipt_cc: ' || LV_ADD_RECIPT_CC ||'  lv_mail_cc1: ' || LV_MAIL_CC1
                        ); 

         L_SUBJECT :=
               'Request '
            || P_LRN_MRN_TYPE
            || ' No- '
            || P_LRN_MRN_NUM
            || ' has been rejected';
         L_BODY :=
               'This is to inform you that Request '
            || P_LRN_MRN_TYPE
            || ' No.- '
            || P_LRN_MRN_NUM
            || ' has been rejected by Approver.';
         L_BODY_LINE_2 :=  'This is Test Email. In case of any query or clarification, kindly mail at ' || LV_MAIL_CC1  || ' .';
         L_BODY_LINE_3 :=
            'Note : This communication is system generated and please do not reply to this email. If you are not the correct recipient for this notification, please contact to Administrator.';
         LV_FILE_NAME := P_LRN_MRN_TYPE || '_' || P_LRN_MRN_NUM || '_FILE.xls';
         
                  APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,'L_SUBJECT: ' || L_SUBJECT
                        );
      END IF;
      
         IF P_MAIL_TYPE = 'RETURN TO CREATOR' AND L_MAIL_TYPE = 'RETURN TO CREATOR'
      THEN
      
           BEGIN
               SELECT PAPF.EMAIL_ADDRESS EMAIL_ADD
                 INTO V_TO_MAIL
                 FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                      APPS.FND_USER FU,
                      APPS.PER_ALL_PEOPLE_F PAPF
                WHERE -1 = -1
                  AND FU.USER_ID = XXH.CREATED_BY
                  AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
                  AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                          AND PAPF.EFFECTIVE_END_DATE
                  AND ORGANIZATION_ID = P_ORGANIZATION_ID
                  AND LRN_NO = P_LRN_MRN_NUM;
            EXCEPTION
               WHEN OTHERS
               THEN
                 V_TO_MAIL := NULL;
            END;
            
           BEGIN
           SELECT LISTAGG(TO_MAIL, ',') WITHIN GROUP(ORDER BY TO_MAIL) EMAIL INTO LV_ADD_RECIPT_CC
             FROM (SELECT DISTINCT RTRIM (LTRIM (ATTRIBUTE1)) TO_MAIL
              FROM FND_LOOKUP_VALUES
                   WHERE LOOKUP_TYPE = 'XXMSSL_INVENTORY_EMAIL_MASTER'
                   AND DESCRIPTION = 'LRN|CC'
                   AND ENABLED_FLAG = 'Y'
                   AND END_DATE_ACTIVE IS NULL
                   AND ATTRIBUTE_CATEGORY = 'EMAIL'
                   AND UPPER(TAG) = UPPER(L_ORGANIZATION_CODE));
            EXCEPTION WHEN OTHERS THEN
                     LV_ADD_RECIPT_CC:= NULL;
                END;
         BEGIN
            SELECT PAPF.FULL_NAME,
                   PAPF.EMAIL_ADDRESS EMAIL_ADD                            
             INTO L_APPROVER,LV_MAIL_CC1
              FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                   APPS.FND_USER FU,
                   APPS.PER_ALL_PEOPLE_F PAPF
             WHERE -1 = -1
               AND FU.USER_ID = P_ACTION_USER
               AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
               AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                       AND PAPF.EFFECTIVE_END_DATE
               AND ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO =  P_LRN_MRN_NUM;
         EXCEPTION
            WHEN OTHERS
            THEN
               L_APPROVER := NULL;
               LV_MAIL_CC1 := NULL;
         END;
                   APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,
                         'V_TO_MAIL: '||V_TO_MAIL||'  lv_add_recipt_cc: ' || LV_ADD_RECIPT_CC ||'  lv_mail_cc1: ' || LV_MAIL_CC1
                        ); 
         L_SUBJECT :=
               'Request '
            || P_LRN_MRN_TYPE
            || ' No- '
            || P_LRN_MRN_NUM
            || ' has been return to creator';
         L_BODY :=
               'This is to inform you that Request '
            || P_LRN_MRN_TYPE
            || ' No.- '
            || P_LRN_MRN_NUM
            || ' has been return to creator by Approver.';
         L_BODY_LINE_2 :=  'This is Test Email. In case of any query or clarification, kindly mail at '  || LV_MAIL_CC1 || ' .';
         L_BODY_LINE_3 :=
            'Note : This communication is system generated and please do not reply to this email. If you are not the correct recipient for this notification, please contact to Administrator.';
         LV_FILE_NAME := P_LRN_MRN_TYPE || '_' || P_LRN_MRN_NUM || '_FILE.xls';
                  APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,'L_SUBJECT: ' || L_SUBJECT
                        );
      END IF;
      
       IF P_MAIL_TYPE = 'COMPLETE' AND L_MAIL_TYPE = 'COMPLETE'
      THEN
      
           BEGIN
               SELECT PAPF.EMAIL_ADDRESS EMAIL_ADD
                 INTO V_TO_MAIL
                 FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                      APPS.FND_USER FU,
                      APPS.PER_ALL_PEOPLE_F PAPF
                WHERE -1 = -1
                  AND FU.USER_ID = XXH.CREATED_BY
                  AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
                  AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                          AND PAPF.EFFECTIVE_END_DATE
                  AND ORGANIZATION_ID = P_ORGANIZATION_ID
                  AND LRN_NO = P_LRN_MRN_NUM;
            EXCEPTION
               WHEN OTHERS
               THEN
                 V_TO_MAIL := NULL;
            END;
            
           BEGIN
           SELECT LISTAGG(TO_MAIL, ',') WITHIN GROUP(ORDER BY TO_MAIL) EMAIL INTO LV_ADD_RECIPT_CC
             FROM (SELECT DISTINCT RTRIM (LTRIM (ATTRIBUTE1)) TO_MAIL
              FROM FND_LOOKUP_VALUES
                   WHERE LOOKUP_TYPE = 'XXMSSL_INVENTORY_EMAIL_MASTER'
                   AND DESCRIPTION in ('LRN|QA','LRN|CC')
                   AND ENABLED_FLAG = 'Y'
                   AND END_DATE_ACTIVE IS NULL
                   AND ATTRIBUTE_CATEGORY = 'EMAIL'
                   AND UPPER(TAG) = UPPER(L_ORGANIZATION_CODE));
            EXCEPTION WHEN OTHERS THEN
                     LV_ADD_RECIPT_CC:= NULL;
                END;
                
         BEGIN
            SELECT PAPF.FULL_NAME,
                   PAPF.EMAIL_ADDRESS EMAIL_ADD                                     
             INTO L_APPROVER,LV_MAIL_CC1
              FROM XXMSSL.XXMSSL_LRN_HEADER_T XXH,
                   APPS.FND_USER FU,
                   APPS.PER_ALL_PEOPLE_F PAPF
             WHERE -1 = -1
               AND FU.USER_ID = XXH.APPROVED_BY
               AND FU.EMPLOYEE_ID = PAPF.PERSON_ID
               AND TRUNC (SYSDATE) BETWEEN PAPF.EFFECTIVE_START_DATE
                                       AND PAPF.EFFECTIVE_END_DATE
               AND ORGANIZATION_ID = P_ORGANIZATION_ID
               AND LRN_NO =  P_LRN_MRN_NUM;
         EXCEPTION
            WHEN OTHERS
            THEN
               L_APPROVER := NULL;
               LV_MAIL_CC1 := NULL;
         END;
                   APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,
                         'V_TO_MAIL: '||V_TO_MAIL||'  lv_add_recipt_cc: ' || LV_ADD_RECIPT_CC ||'  lv_mail_cc1: ' || LV_MAIL_CC1
                        ); 
         L_SUBJECT :=
               'Request '
            || P_LRN_MRN_TYPE
            || ' No- '
            || P_LRN_MRN_NUM
            || ' has been Complete';
         L_BODY :=
               'This is to inform you that Request '
            || P_LRN_MRN_TYPE
            || ' No.- '
            || P_LRN_MRN_NUM
            || ' has been complete.';
         L_BODY_LINE_2 := 'This is Test Email. In case of any query or clarification, kindly mail at '  || LV_MAIL_CC1  || ' .';
         L_BODY_LINE_3 :=
            'Note : This communication is system generated and please do not reply to this email. If you are not the correct recipient for this notification, please contact to Administrator.';
         LV_FILE_NAME := P_LRN_MRN_TYPE || '_' || P_LRN_MRN_NUM || '_FILE.xls';
                  APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                         'EMAIL Notification',
      P_LRN_MRN_NUM,'L_SUBJECT: ' || L_SUBJECT
                        );
      END IF;

      IF V_TO_MAIL IS NOT NULL
      THEN
         IF LV_ADD_RECIPT_CC IS NOT NULL  --  TO Email Addition 
         THEN
            V_TO_MAIL := V_TO_MAIL || ';' || LV_ADD_RECIPT_CC;
         END IF;  
      
         IF LV_MAIL_CC1 IS NOT NULL -- CC Email
         THEN
            V_CC_MAIL := LV_MAIL_CC1;
         END IF;

         IF LV_MAIL_CC2 IS NOT NULL -- CC Email Addition 
         THEN
            V_CC_MAIL := LV_MAIL_CC2 || ';' ||  V_CC_MAIL ;
         END IF;

         
         
                APPS.XXMSSL_LRN_PKG.PRINT_LOG (
                        'EMAIL Notification',
      P_LRN_MRN_NUM, 'V_TO_MAIL: '||V_TO_MAIL
                        ); 
                   APPS.XXMSSL_LRN_PKG.PRINT_LOG (
                       'EMAIL Notification',
      P_LRN_MRN_NUM,  'lv_mail_cc1: '||LV_MAIL_CC1
                        );    
                        
                       APPS.XXMSSL_LRN_PKG.PRINT_LOG (
                        'EMAIL Notification',
      P_LRN_MRN_NUM, 'lv_mail_cc2: '||LV_MAIL_CC2
                        );     
                        
                          APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                        'EMAIL Notification',
      P_LRN_MRN_NUM, 'lv_add_recipt_cc: '||LV_ADD_RECIPT_CC
                        );  
                        
                        APPS.XXMSSL_LRN_PKG.PRINT_LOG  (
                        'EMAIL Notification',
      P_LRN_MRN_NUM, 'V_TO_MAIL: '||V_TO_MAIL
                        );
                        
                         APPS.XXMSSL_LRN_PKG.PRINT_LOG (
                       'EMAIL Notification',
      P_LRN_MRN_NUM,  'v_cc_mail: '||V_CC_MAIL
                        );     
         

         LV_QUERY :=
               'SELECT DISTINCT xlh.lrn_no, xld.lrn_type, xld.line_num, xld.item_code,xld.CATEGORY,
                xld.item_description, xld.lrn_quantity, xld.subinventory_code,
                xld.lrn_reason_code,
                xlh.lrn_status, xld.job_number, xld.qty_return_to_stores,
                xld.reject_quantity, xld.scrapped_quantity, xld.return_qty,
                xld.rejection_defect_reason, xld.rejection_lrn_type,
                xld.rejection_lrn_reason, xld.scrap_defect_reason,
                xld.scrap_lrn_type, xld.scrap_lrn_reason, xld.inspected_date,
                xld.inspected_by, xlh.move_order_number
          FROM  xxmssl.xxmssl_lrn_header_t xlh,
                xxmssl.xxmssl_lrn_detail_t xld
          WHERE xlh.lrn_no = xld.lrn_no
            AND xlh.organization_id = '
            || CHR (39)
            || P_ORGANIZATION_ID
            || CHR (39)
            || '
            AND xlh.lrn_no = '
            || CHR (39)
            || P_LRN_MRN_NUM
            || CHR (39)
            || '';
         APPS.XXMSSL_LRN_PKG.P_MAIL_ATTACHMENT
            (P_TO               => V_TO_MAIL,
             P_CC               => V_CC_MAIL,
             P_FROM             => SENDER,
             P_SUBJECT          => L_SUBJECT,
             P_TEXT_MSG         =>    '<html><body><br> Dear Sir/Madam, <br><br>'
                                   || L_BODY
                                  -- || '</br><br>'|| L_BODY_LINE_2|| '<br><br> Regards <br>'|| L_APPROVER
                                   || '<br><br>'
                                   || L_BODY_LINE_3
                                   || '
                                       </body></html>',
             P_ATTACH_NAME      => LV_FILE_NAME,
             P_ATTACH_MIME      => 'application/octet-stream',
             P_SMTP_HOST        => MAILHOST,
             P_SQL              => LV_QUERY
            );
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         PRINT_LOG ('error in mail report program ' || SQLERRM
                           );
   END;
END XXMSSL_LRN_PKG; 
/
