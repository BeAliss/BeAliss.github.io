USE [tg]
GO
/****** Object:  StoredProcedure [dbo].[spControlTG]    Script Date: 09.06.2018 14:38:47 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<МТА>
-- Create date: <26.12.14>   Last modified: 06.02.2015 by A.S. Lvov
-- Description:	<Контроль снижения выработки мощности на 20% на ТГ, отправка СМС>
-- =============================================
ALTER PROCEDURE [dbo].[spControlTG]
AS
BEGIN
declare   @date datetime
set @date  = GetDate();
declare @cntID varchar(16),
        @dt datetime,
		@P int,
        @Pn int,
		@taskID int,
		@taskIDmax int,
        @taskIDmax1 int,  
        @taskIDmax2 int,
        @textmessage		 varchar(500),
		@textmessage1 varchar(500),
		@name  varchar(15),

		@lastErrorTime datetime;
DECLARE @strCmdLineText varchar(8000);

 UPDATE [dbo].[StateTg]
		set [snapShotTime] =  @date
  BEGIN TRY 

 
   SELECT @taskIDmax1 = MaxTaskId
   FROM OPENQUERY(CSS, 'select   MAX(TaskId) AS MaxTaskId  FROM TTLCTRL.dbo.tbl_SmsQueue')
   
    
   set @taskIDmax2 =  (select  max(isnull(taskID,0))  FROM tg.dbo.StateTg)
   set @taskIDmax = (select case when (@taskIDmax1>=@taskIDmax2) then @taskIDmax1 else  @taskIDmax2 end ) 

DECLARE t_cursor cursor FOR 

  SELECT  cntID,dt,P
   FROM [AIIS-DB].aiisArch.dbo.cv1m cv inner join tg.dbo.StateTg st on  cv.cntID = st.cellID
    and dt  between   DATEADD(mi,-1,@date) and @date
FOR READ ONLY;

	OPEN t_cursor;
		FETCH NEXT FROM t_cursor INTO @cntID, @dt,@P;
		
		WHILE @@FETCH_STATUS = 0 
	    BEGIN
		
		set @Pn = (select  PNominal  FROM tg.dbo.PNominal where cellID = @cntID)
       	if  @P <  @Pn*0.8
		   BEGIN
		   set @taskID = (select  taskID  FROM tg.dbo.StateTg where cellID = @cntID)
	     print @taskID
		    IF @taskID is  null
			        BEGIN 
			        UPDATE dbo.StateTg
		            SET lastErrorTime =  @date,
		                taskID  = @taskIDmax+1
		            where cellID = @cntID;
					set @taskIDmax = @taskIDmax+1;
					END
             ELSE
			      BEGIN
				  set @lastErrorTime = (select  lastErrorTime  FROM tg.dbo.StateTg where cellID = @cntID)
                				  
				  if DATEDIFF(mi, @lastErrorTime ,@date) > 10
				      BEGIN
					  DECLARE @nRemTaslId int,
                              @wstrRemoteQry nvarchar(200) = N'''SELECT TaskId ' +
                                                            'FROM  TTLCTRL.dbo.tbl_SmsQueue ' +  
                                                            'WHERE  TaskId = ' 

                      SET @wstrRemoteQry = N'SELECT @nRemoteTaskId = TaskId ' +
                                          'FROM ' +
                                          'OPENQUERY(CSS, ' + @wstrRemoteQry + CONVERT(nvarchar(10), @taskID) + ''')';
										  
                      EXEC sp_executesql @wstrRemoteQry, N'@nRemoteTaskId int OUTPUT', @nRemoteTaskId = @nRemTaslId OUTPUT

                      IF @nRemTaslId IS NULL
						BEGIN
						set @name = (select name  
						             FROM   tg.dbo.PNominal 
									 where  cellID = @cntID)

						declare @telef        varchar(200) = '',
						        @strEMailList varchar(500) = ''

						SELECT @telef        = @telef + telef + ';', 
						       @strEMailList = @strEMailList + EMail + ';'
                        FROM   tg.dbo.TgUser u INNER JOIN tg.dbo.LinksTgUser l ON u.ID_user = l.ID_user
						       AND  (cntID = @cntID OR cntID = 'all')

						/*set  @textmessage = @name+': Сниж-е c ' + convert(varchar(15),@lastErrorTime,108)+' '+convert(varchar(15),@lastErrorTime,104) +
						'(P=' + CAST (@Pn as VARCHAR(15)) + 'кВт, P=' +CAST (@P as VARCHAR(15))+'кВт)';*/
						SET  @textmessage = @name + ': Снижение выработки с ' + 
						    CONVERT(varchar(10), @lastErrorTime, 108) + ' ' + 
							CONVERT(varchar(10) ,@lastErrorTime, 104) +
						    ' более 10 мин (Pnom = ' + CAST (@Pn as varchar(10)) + 
							' кВт, P = ' + CAST (@P as varchar(10)) + ' кВт)';
						set  @textmessage1 = @textmessage + +' телефоны для смс:'+substring(@telef,1,len(@telef)-1)+ '@taskID +   '+ CAST (@taskID as VARCHAR(15));
						
						--exec CSS.TTLCTRL.dbo.[sp_SendSms] @telef, @textmessage;
						EXEC CSS.TTLCTRL.dbo.sp_SmsQueue_EnqueueRdd   @taskID, @telef, @textmessage, 1
				
						SET @strCmdLineText = 'C:\Utilities\MailUtil\MailUtil.exe ' + 
						    '"http://electro.cesa.int/tec/SendViaSmtp.aspx" "' + @strEMailList     + 
							'tamilovskaya@severstal.com" "' + @textmessage + --;tamilovskaya@severstal.com
							'" "' /*+@textmessage1*/ + @name + 
						    ': снижение выработки на ТГ более 10 минут" '   + 
							'"SEVERSTAL\aiiscue" aHNLVzc2NSo='
                        PRINT @strCmdLineText
				        EXEC master..xp_cmdshell @strCmdLineText
						END;
					 END;
		           END;
            	END;
        ELSE
		begin
		 UPDATE dbo.StateTg
		            SET lastErrorTime =  null,
		                taskID  =null
		            where cellID = @cntID;
		end
		FETCH NEXT FROM t_cursor INTO @cntID, @dt,@P;
		END;--WHILE @@FETCH_STATUS = 0
		CLOSE t_cursor;
		DEALLOCATE t_cursor;


END TRY

    BEGIN CATCH
        DECLARE @wstrErrorMessage nvarchar(4000)
        SET @wstrErrorMessage = 'Процедура spControlTG  - отправка сообщений - сбой. ' + ERROR_MESSAGE();        
    
        EXEC xp_logevent 100182, @wstrErrorMessage, WARNING
    END CATCH
END
