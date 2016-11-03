/*
   *******************************************************************
   *  SQL Script to migrate DNN active Forum to YAF.Net DNN module   *
   *  ============================================================   *
   *                                                                 *
   *  (c) Sebastian Leupold, dnnWerk, 2016                           *
   *                                                                 *
   *******************************************************************
*/
PRINT 'Temporarily add referring columns to YAF.Net tables:';
IF NOT Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_Board')    AND name = N'oModuleID')
  ALTER TABLE dbo.yaf_board    ADD oModuleID  Int Null;

IF NOT Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_Category') AND name = N'oGroupID')
  ALTER TABLE dbo.yaf_category ADD oGroupID   Int Null;

IF NOT Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_Forum')    AND name = N'oForumID')
  ALTER TABLE dbo.yaf_forum    ADD oForumID   Int Null;

IF NOT Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_Topic')    AND name = N'oTopicID')
  ALTER TABLE dbo.yaf_Topic    ADD oTopicID   Int Null;

IF NOT Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_Message')  AND name = N'oContentID')
  ALTER TABLE dbo.yaf_Message  ADD oContentID Int Null;

GO

/* Specify your original moduleID here:               */
DECLARE @oModuleID int = 504;
/*                       ^ replace with your ModuleID */
/* -------------------------------------------------- */
/* modify the following id's to match the board,
  you want to use as template:                        */
BEGIN TRANSACTION;

BEGIN TRY
--  DECLARE @oModuleID     int = 553; -- Test only --
	DECLARE @tplBoardID    int = 1;
	/* -------------------------------------------------- */

	-- Get PortalID:
	PRINT N'*** start migration (this may take some time) ***';
	DECLARE @oPortalID   int = (SELECT PortalID FROM dbo.Modules WHERE ModuleID = @oModuleID);
	DECLARE @TZOffsetMin int = - DATEPART(TZOFFSET, SYSDATETIMEOFFSET());

	PRINT N'Create YAF.Net Board:';
	INSERT INTO dbo.yaf_Board
		   (Name, allowThreaded, MembershipAppName, RolesAppName, oModuleID)
	SELECT ModuleTitle, 1, N'', N'', ModuleID
	 FROM  dbo.TabModules
	 WHERE TabModuleID IN (SELECT Min(TabModuleID) FROM dbo.TabModules WHERE ModuleID = @oModuleID);

	-- get the boardID:
	DECLARE @boardID int = (SELECT BoardID FROM dbo.yaf_Board WHERE oModuleID = @oModuleID);

	PRINT N'Create accessMasks:';
	MERGE INTO dbo.yaf_AccessMask  T
	USING (SELECT @boardID as BoardID, [Name], [Flags], SortOrder FROM dbo.yaf_AccessMask WHERE BoardID = @tplBoardID) S
		   ON T.BoardID = S.BoardID and T.SortOrder = S.SortOrder
	WHEN NOT MATCHED THEN INSERT (  BoardID, [Name], [Flags],   SortOrder)
						  VALUES (S.BoardID, S.Name, S.Flags, S.SortOrder);

	PRINT N'Create YAF Groups from DNN Roles (only used ones)';
	PRINT N'a. Create default Roles:';
	MERGE INTO dbo.yaf_Group T
	USING (SELECT * FROM dbo.yaf_Group WHERE BoardID = @tplBoardID and Flags != 0) S ON T.BoardID = @BoardID AND T.Name = S.Name
	WHEN NOT MATCHED THEN INSERT ( BoardID,   [Name],   [Flags],   PMLimit,   Style,   SortOrder,   Description,   UsrSigChars,   UsrSigBBCodes,   UsrSigHTMLTags,   UsrAlbums,   UsrAlbumImages)
						  VALUES (@BoardID, S.[Name], S.[Flags], S.PMLimit, S.Style, S.SortOrder, S.Description, S.UsrSigChars, S.UsrSigBBCodes, S.UsrSigHTMLTags, S.UsrAlbums, S.UsrAlbumImages);

	PRINT N'b. Create individual Roles:';
	MERGE INTO dbo.yaf_Group T
	USING (SELECT RoleName FROM dbo.Roles
			WHERE RoleID     IN (SELECT DISTINCT RoleID FROM dbo.ModulePermission P WHERE P.ModuleID = @oModuleID)
			  AND RoleID NOT IN (SELECT RoleID FROM dbo.Roles R JOIN dbo.Portals P ON R.PortalID = P.PortalID JOIN dbo.Modules M ON P.PortalID = M.PortalID  WHERE M.ModuleID = @oModuleID)
		  ) S  ON T.BoardID = @BoardID AND T.Name = S.RoleName
	WHEN NOT MATCHED THEN INSERT (BoardID, [Name],    [Flags], PMLimit, Style, SortOrder, Description, UsrSigChars, UsrSigBBCodes, UsrSigHTMLTags, UsrAlbums, UsrAlbumImages)
						  VALUES (@BoardID, S.RoleName,     0,       0,  Null,       100,         N'',           0,           N'',            N'',         0,              0);


	PRINT N'Populate Ranks:';
	MERGE INTO dbo.yaf_Rank T
	USING (SELECT * FROM dbo.yaf_Rank WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.Name = S.Name
	WHEN NOT MATCHED THEN INSERT ( BoardID,   [Name],   MinPosts,   RankImage,   Flags,   PMLimit,   Style,   SortOrder,   Description,   UsrSigChars,   UsrSigBBCodes,   UsrSigHTMLTags,   UsrAlbums,   UsrAlbumImages)
						  VALUES (@BoardID, S.[Name], S.MinPosts, S.RankImage, S.Flags, S.PMLimit, S.Style, S.SortOrder, S.Description, S.UsrSigChars, S.UsrSigBBCodes, S.UsrSigHTMLTags, S.UsrAlbums, S.UsrAlbumImages);

	DECLARE @newRank smallint = (SELECT RankId FROM dbo.yaf_Rank WHERE BoardID = @boardID AND MinPosts = 0);

	PRINT N'Populate Smileys:';
	MERGE INTO dbo.yaf_Smiley T
	USING (SELECT * FROM dbo.yaf_Smiley WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.SortOrder = S.SortORder
	WHEN NOT MATCHED THEN INSERT ( BoardID,   [Code],   Icon,   Emoticon,   SortOrder)
						  VALUES (@BoardID, S.[Code], S.Icon, S.Emoticon, S.SortOrder);

	PRINT N'Populate SpamWords:';
	MERGE INTO dbo.yaf_Spam_Words T
	USING (SELECT * FROM dbo.yaf_Spam_Words WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.SpamWord = S.SpamWord
	WHEN NOT MATCHED THEN INSERT ( BoardID,   SpamWord)
						  VALUES (@BoardID, S.SpamWord);

	PRINT N'Populate Replace_Words:';
	MERGE INTO dbo.yaf_Replace_Words T
	USING (SELECT * FROM dbo.yaf_Replace_Words WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.BadWord = S.BadWord
	WHEN NOT MATCHED THEN INSERT ( BoardID,   BadWord,   GoodWord)
						  VALUES (@BoardID, S.BadWord, S.GoodWord);

	PRINT N'Populate Extensions:';
	MERGE INTO dbo.yaf_Extension T
	USING (SELECT * FROM dbo.yaf_Extension WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.Extension = S.Extension
	WHEN NOT MATCHED THEN INSERT ( BoardID,   Extension)
						  VALUES (@BoardID, S.Extension);

	PRINT N'Populate BBCodes:';
	MERGE INTO dbo.yaf_BBCode T
	USING (SELECT * FROM dbo.yaf_BBCode WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.Name = S.Name
	WHEN NOT MATCHED THEN INSERT ( BoardID,   [Name],   Description,   OnClickJS,   DisplayJS,   EditJS,   DisplayCSS,   SearchRegex,   ReplaceRegex,   Variables,   UseModule,   ModuleClass,   ExecOrder)
						  VALUES (@BoardID, S.[Name], S.Description, S.OnClickJS,   DisplayJS, S.EditJS, S.DisplayCSS, S.SearchRegex, S.ReplaceRegex, S.Variables, S.UseModule, S.ModuleClass, S.ExecOrder);

	PRINT N'Populate TopicStatus:';
	MERGE INTO dbo.yaf_TopicStatus T
	USING (SELECT * FROM dbo.yaf_TopicStatus WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.TopicStatusName = S.TopicStatusName
	WHEN NOT MATCHED THEN INSERT ( BoardID,   TopicStatusName,   defaultDescription)
						  VALUES (@BoardID, S.TopicStatusName, S.defaultDescription);

	PRINT N'Populate YAF.Net Registry:';
	MERGE INTO dbo.yaf_Registry T
	USING (SELECT * FROM dbo.yaf_Registry WHERE BoardID = @tplBoardID) S ON T.BoardID = @BoardID AND T.[Name] = S.[Name]
	WHEN NOT MATCHED THEN INSERT ( BoardID,   [Name],   Value)
						  VALUES (@BoardID, S.[Name], S.Value);

	PRINT N'Create ASP.Net Roles:';
	DECLARE @appGuid uniqueIdentifier = (SELECT ApplicationID FROM dbo.aspnet_applications WHERE ApplicationName = N'DotNetNuke' OR ApplicationName = N'DNN');
	MERGE INTO dbo.aspnet_Roles T
	USING (SELECT * FROM dbo.yaf_Group WHERE BoardID = @BoardID) S ON T.RoleName = S.Name
	WHEN NOT MATCHED THEN INSERT (ApplicationID, RoleID, RoleName, LoweredRoleName, Description)
						  VALUES (@appGuid,     NewID()  , S.Name,   Lower(S.Name),        Null);


	-- Populate Users:
	/* YAF User Flags: None = 0, IsHostAdmin = 1, IsApproved = 2, IsGuest = 4, IsCaptchaExcluded = 8, IsActiveExcluded = 16, IsDST = 32, IsDirty = 64 */
	DECLARE @DefaultTimeZoneOffset SmallInt = (SELECT TimezoneOffset FROM dbo.Portals WHERE PortalID = @oPortalID);
	DECLARE @TZPropertyID          Int      = (SELECT PropertyDefinitionID FROM dbo.ProfilePropertyDefinition WHERE PortalID = @oPortalID
												AND DataType = (SELECT EntryID FROM dbo.Lists WHERE ListName = N'DataType' AND Value = N'TimeZone'));
	DECLARE @BDPropertyID          Int      = (SELECT PropertyDefinitionID FROM dbo.ProfilePropertyDefinition WHERE PortalID = @oPortalID AND PropertyName = N'Birthday');
	DECLARE @CNPropertyID          Int      = (SELECT PropertyDefinitionID FROM dbo.ProfilePropertyDefinition WHERE PortalID = @oPortalID AND PropertyName = N'Country');
	DECLARE @RGPropertyID          Int      = (SELECT PropertyDefinitionID FROM dbo.ProfilePropertyDefinition WHERE PortalID = @oPortalID AND PropertyName = N'Region');
	DECLARE @CYPropertyID          Int      = (SELECT PropertyDefinitionID FROM dbo.ProfilePropertyDefinition WHERE PortalID = @oPortalID AND PropertyName = N'City');
	DECLARE @WSPropertyID          Int      = (SELECT PropertyDefinitionID FROM dbo.ProfilePropertyDefinition WHERE PortalID = @oPortalID AND PropertyName = N'Website');

	PRINT N'Create Guest User:';
	MERGE INTO dbo.yaf_user T
	USING (SELECT * FROM dbo.yaf_User WHERE BoardID = @tplBoardID AND Name = N'Guest') S ON T.BoardID = @BoardID and T.Name = S.Name
	WHEN NOT MATCHED THEN INSERT ( BoardID,   ProviderUserKey,   Name,   DisplayName,   Password,   Email,   Joined,   LastVisit,   IP,   NumPosts,   TimeZone,   Avatar,   Signature,   AvatarImage,   AvatarImageType,   RankID,   Suspended,   SuspendedReason,   SuspendedBy,   LanguageFile,   ThemeFile,   TextEditor,   OverridedefaultThemes,   PMNotification,   AutoWatchTopics,   DailyDigest,   NotificationType,   Flags,   Points,   Culture,   IsFacebookUser,   IsTwitterUser,   UserStyle,   StyleFlags,   IsGoogleUser)
						  VALUES (@BoardID, S.ProviderUserKey, S.Name, S.DisplayName, S.Password, S.Email, S.Joined, S.LastVisit, S.IP, S.NumPosts, S.TimeZone, S.Avatar, S.Signature, S.AvatarImage, S.AvatarImageType, S.RankID, S.Suspended, S.SuspendedReason, S.SuspendedBy, S.LanguageFile, S.ThemeFile, S.TextEditor, S.OverridedefaultThemes, S.PMNotification, S.AutoWatchTopics, S.DailyDigest, S.NotificationType, S.Flags, S.Points, S.Culture, S.IsFacebookUser, S.IsTwitterUser, S.UserStyle, S.StyleFlags, S.IsGoogleUser);

	Print N'create all other users, who ever created a post:';
	WITH xUsers AS
		(SELECT U.*,
				A.UserId AS UserKey,
				P.Signature,
				P.Avatar,
				P.TopicCount + P.ReplyCount AS NumPosts,
				IsNull(cast(PropertyValue AS smallint), @DefaultTimeZoneOffset) AS TZOffset
		FROM      dbo.Users                     U
			 JOIN dbo.aspnet_users              A ON U.UserName = A.UserName
			 JOIN dbo.activeforums_UserProfiles P ON U.UserID   = P.UserId AND P.PortalId = @oPortalID
		LEFT JOIN dbo.UserProfile               T ON U.UserID   = T.UserID AND T.PropertyDefinitionID = @TZPropertyID
	  )
		MERGE INTO dbo.yaf_user T
		USING xUsers S ON T.BoardID = @BoardID and T.Name = S.UserName
		WHEN NOT MATCHED THEN INSERT ( BoardID, ProviderUserKey,       Name,   DisplayName, Password,   Email,       Joined,    LastVisit,   IP,   NumPosts,   TimeZone,   Avatar,   Signature, AvatarImage, AvatarImageType,   RankID, Suspended, SuspendedReason, SuspendedBy, LanguageFile, ThemeFile, TextEditor, OverridedefaultThemes, PMNotification, AutoWatchTopics, DailyDigest, NotificationType, Flags, Points, Culture, IsFacebookUser, IsTwitterUser, UserStyle, StyleFlags, IsGoogleUser)
							  VALUES (@BoardID,       S.UserKey, S.UserName, S.DisplayName,    N'na', S.Email, GetUTCDate(), GetUTCDate(), Null, S.NumPosts, S.TZOffset, S.Avatar, S.Signature,        Null,            Null, @newRank,         0,            Null,           0,         Null,      Null,       Null,                     1,              1,               0,           0,                0,     2,      0,    Null,              0,             0,      Null,          0,            0);


	PRINT N'Populate UserProfile:';
	WITH xProfile AS
		(SELECT Y.UserID,
				U.Username,
				U.DisplayName,
				DateAdd(n, @TZOffsetMin, U.LastModifiedOnDate) AS LastUpdatedDate, -- TZ shifted
				DateAdd(n, @TZOffsetMin, P.DateLastActivity)   AS LastActivity,    -- TZ shifted
				Cast(IsNull(BD.PropertyValue, '1903-01-01T00:00:00') as date) AS BirthDay,
				CN.PropertyText  AS Country,
				RG.PropertyText  AS Region,
				CY.PropertyValue AS City,
				WS.PropertyValue AS Website
		  FROM      dbo.yaf_User                  Y
		  JOIN      dbo.Users                     U  ON Y.Name	  = U.Username AND Y.BoardID  = @boardID
		  JOIN      dbo.activeforums_UserProfiles P  ON U.UserID  = P.UserId   AND P.PortalId = @oPortalID
		  LEFT JOIN dbo.UserProfile               BD ON U.UserID  = BD.UserID  AND BD.PropertyDefinitionID = @BDPropertyID
		  LEFT JOIN dbo.UserProfile               CN ON U.UserID  = CN.UserID  AND CN.PropertyDefinitionID = @CNPropertyID
		  LEFT JOIN dbo.UserProfile               RG ON U.UserID  = RG.UserID  AND RG.PropertyDefinitionID = @RGPropertyID
		  LEFT JOIN dbo.UserProfile               CY ON U.UserID  = BD.UserID  AND BD.PropertyDefinitionID = @BDPropertyID
		  LEFT JOIN dbo.UserProfile               WS ON U.UserID  = WS.UserID  AND WS.PropertyDefinitionID = @WSPropertyID
		)
        MERGE INTO dbo.yaf_prov_Profile T
		USING xProfile S ON T.UserID = S.UserID
		WHEN NOT MATCHED THEN INSERT (  UserID,   LastUpdatedDate,  Gender,   Blog,      RealName, Interests, Skype, Facebook, Location, BlogServiceUrl,   Birthday, LastSyncedWithDNN, ICQ,   City, MSN, TwitterId, Twitter, BlogServicePassword,   Country, Occupation,   Region, AIM, XMPP, YIM, Google, BlogServiceUsername, GoogleId,  Homepage, FacebookId)
							  VALUES (S.UserID, S.LastUpdatedDate, 0,    N'', S.DisplayName,       N'',   N'',      N'',      N'',            N'', S.Birthday,              Null, N'', S.City, N'',      Null,     N'',                 N'', S.Country,        N'', S.Region, N'',  N'', N'',    N'',                 N'',     Null, S.Website,       Null);

	PRINT N'Add Guests Membership for Guest User;';
	With S AS
		(SELECT Y.UserID,
				G.GroupID
		  FROM  dbo.yaf_Group G
		  JOIN  dbo.yaf_User  Y ON Y.Name = N'Guest' AND Y.BoardID  = G.BoardID AND G.Flags = 2
		  WHERE G.BoardID  = @BoardID
		)
		MERGE INTO dbo.yaf_userGroup T
		USING S ON T.UserID = S.UserID and T.GroupID = S.GroupID
		WHEN NOT MATCHED THEN INSERT (UserID, GroupID) VALUES (S.UserID, S.GroupID);

	PRINT N'Add All users to Registered Group;';
	With S AS
		(SELECT Y.UserID,
				G.GroupID
		  FROM  dbo.yaf_Group G
		  JOIN  dbo.yaf_User  Y ON Y.Name != N'Guest' AND Y.BoardID  = G.BoardID AND G.Flags = 4
		  WHERE G.BoardID  = @BoardID
		)
		MERGE INTO dbo.yaf_userGroup T
		USING S ON T.UserID = S.UserID and T.GroupID = S.GroupID
		WHEN NOT MATCHED THEN INSERT (UserID, GroupID) VALUES (S.UserID, S.GroupID);

	PRINT N'Add Superusers to Administrators Group;';
	With S AS
		(SELECT Y.UserID,
				G.GroupID
		  FROM  dbo.yaf_Group G
		  JOIN  dbo.yaf_User  Y ON  Y.BoardID  = G.BoardID AND G.Flags = 1
		  JOIN  dbo.Users     U ON  U.UserName = Y.Name AND U.IsSuperUser = 1
		  WHERE G.BoardID  = @BoardID
		)
		MERGE INTO dbo.yaf_userGroup T
		USING S ON T.UserID = S.UserID and T.GroupID = S.GroupID
		WHEN NOT MATCHED THEN INSERT (UserID, GroupID) VALUES (S.UserID, S.GroupID);

	PRINT N'Populate UserGroups:';
	With S AS
		(SELECT Y.UserId,
				G.GroupID
		  FROM dbo.UserRoles X
		  JOIN dbo.Roles     R ON X.RoleID = R.RoleID AND R.PortalID = @oPortalID
		  JOIN dbo.yaf_Group G ON R.RoleName = G.Name AND G.BoardID  = @BoardID
		  JOIN dbo.Users     U ON X.UserID   = U.UserID
		  JOIN dbo.yaf_User  Y ON U.Username = Y.Name AND Y.BoardID  = @BoardID
		)
		MERGE INTO dbo.yaf_userGroup T
		USING S ON T.UserID = S.UserID and T.GroupID = S.GroupID
		WHEN NOT MATCHED THEN INSERT (UserID, GroupID) VALUES (S.UserID, S.GroupID);

	PRINT N'Raise Access Mask for Administrators:';
	MERGE INTO dbo.yaf_User T
	USING (SELECT UserID
			FROM  dbo.yaf_UserGroup R
			JOIN  dbo.yaf_Group     G ON R.GroupID = G.GroupID
			WHERE G.Flags = 1 AND G.BoardID = @BoardID
		   ) S ON T.UserID = S.UserID
	WHEN MATCHED AND T.Flags != 98 THEN UPDATE SET FLAGS = 98;

	PRINT N'Raise Access Mask for Superusers:';
	MERGE INTO dbo.yaf_User T
	USING (SELECT R.UserID
			FROM  dbo.yaf_UserGroup R
			JOIN  dbo.yaf_Group     G ON R.GroupID = G.GroupID
			JOIN  dbo.yaf_user      Y ON R.UserID = Y.UserID
			JOIN  dbo.Users         U ON U.UserName = Y.Name AND U.isSuperuser = 1
			WHERE G.Flags = 1 AND G.BoardID = @BoardID
		   ) S ON T.UserID = S.UserID
	WHEN MATCHED AND T.Flags != 99 THEN UPDATE SET FLAGS = 99;

	Print 'Populate aspnet_usersInRoles:';
	MERGE INTO dbo.aspnet_usersInRoles T
	USING (SELECT U.ProviderUserKey AS UserId,
	              R.RoleID
	        FROM  dbo.yaf_UserGroup  Y
			JOIN  dbo.yaf_Group      G ON Y.GroupID = G.GroupID
	        JOIN  dbo.aspnet_Roles   R ON G.Name = R.RoleName AND G.BoardID = @BoardID
			JOIN  dbo.yaf_User       U ON Y.UserID = U.UserID
			WHERE U.ProviderUserKey Is Not Null
	      ) S ON T.UserID = S.UserID and T.RoleID = S.RoleID
	WHEN NOT MATCHED THEN INSERT (UserID, RoleID) VALUES (S.UserID, S.RoleID);


	PRINT N'Copy AF Forum Groups to YAF.Net Categories:';
	MERGE INTO dbo.yaf_category T
	USING (SELECT * FROM dbo.activeforums_Groups WHERE ModuleID = @oModuleID) S ON T.BoardID = @BoardID AND T.Name = S.GroupName
	WHEN NOT MATCHED THEN INSERT ( BoardID,     [Name],              CategoryImage,   SortOrder, PollgroupID, oGroupID)
						  VALUES (@BoardID,  GroupName, N'categoryImageSample.gif', S.SortOrder, Null,  S.ForumGroupID);

	PRINT N'Copy AF Forums to YAF.Net Forums (parent forums):';
	MERGE INTO dbo.yaf_forum T
	USING (SELECT F.*,
				  Left(F.ForumName,  50) AS FName,
				  Left(F.ForumDesc, 255) AS FDesc,
				  DateAdd(n, @TZOffsetMin, F.LastPostDate) AS LPDate,
				  F.TotalTopics + F.TotalReplies AS TPosts,
				  C.CategoryID
			FROM  dbo.activeforums_Forums F
			JOIN  dbo.yaf_category        C ON F.ForumGroupID = C.oGroupID
			WHERE F.ParentForumID = 0
		  ) S ON S.CategoryID = T.CategoryID AND T.Name = S.ForumName
	WHEN NOT MATCHED THEN INSERT (  CategoryID,   ParentID,  [Name], Description, SortOrder, LastPosted, LastTopicID, LastMessageID, LastUserID, LastUserName, LastUserDisplayName,     NumTopics, NumPosts, RemoteURL, Flags, ThemeURL, PollGroupID, ImageURL, Styles, IsModeratedNewTopicOnly, oForumID)
						  VALUES (S.CategoryID,       Null, S.FName,     S.FDesc, S.SortOrder, S.LPDate,        Null,          Null,       Null,         Null,                Null, S.TotalTopics, S.TPosts,      Null,     4,     Null,        Null,     Null,   Null,                      0, S.ForumID);

	PRINT N'Copy AF Forums to YAF.Net Forums (child forums):';
	MERGE INTO dbo.yaf_forum T
	USING (SELECT F.*,
				  Left(F.ForumName,  50) AS FName,
				  Left(F.ForumDesc, 255) AS FDesc,
				  DateAdd(n, @TZOffsetMin, F.LastPostDate) AS LPDate,
				  F.TotalTopics + F.TotalReplies AS TPosts,
				  C.CategoryID,
				  Y.ForumID As ParentID
			FROM  dbo.activeforums_Forums F
			JOIN  dbo.yaf_Category        C ON F.ForumGroupID  = C.oGroupID
			JOIN  dbo.yaf_Forum           Y ON F.ParentForumID = Y.oForumID
		  ) S ON S.CategoryID = T.CategoryID AND T.Name = S.ForumName
	WHEN NOT MATCHED THEN INSERT (  CategoryID,   ParentID,  [Name], Description, SortOrder, LastPosted, LastTopicID, LastMessageID, LastUserID, LastUserName, LastUserDisplayName,     NumTopics, NumPosts, RemoteURL, Flags, ThemeURL, PollGroupID, ImageURL, Styles, IsModeratedNewTopicOnly, oForumID)
						  VALUES (S.CategoryID, S.ParentID, S.FName,     S.FDesc, S.SortOrder, S.LPDate,        Null,          Null,       Null,         Null,                Null, S.TotalTopics, S.TPosts,      Null,     4,     Null,        Null,     Null,   Null,                      0, S.ForumID);

	/* YAF Topic Flags: None = 0, IsLocked = 1, IsDeleted = 8, IsPersistent = 512, IsQuestion = 1024 */
	PRINT N'Create Threads:';
	MERGE INTO dbo.yaf_topic T
	USING (SELECT T.*,
	              CASE T.StatusID WHEN 0 THEN N'INFORMATIC' WHEN 1 THEN N'QUESTION' WHEN 3 THEN N'SOLVED' ELSE N'' END AS YState,
				    CASE WHEN T.isDeleted = 1 THEN    8 ELSE 0 END
				  + CASE WHEN T.IsLocked  = 1 THEN    1 ELSE 0 END
				  + CASE WHEN T.IsPinned  = 1 THEN    0 ELSE 0 END -- no equivalent?
				  + CASE WHEN T.StatusID  = 1 THEN 1024 ELSE 0 END AS YFlags,
				  DateAdd(n, @TZOffsetMin, DateAdd(ss, X.LastTopicDate, '01/01/1970 00:00:00 AM')) AS LastTopicDate, -- TZ shifted
				  DateAdd(n, @TZOffsetMin, DateAdd(ss, X.LastReplyDate, '01/01/1970 00:00:00 AM')) AS LastReplyDate, -- TZ shifted
				  X.LastReplyID,
				  Y1.UserID      AS AuthorID,
				  Y1.DisplayName AS AuthorName,
				  Left(C.Subject, 100) AS Subject,
				  DateAdd(n, @TZOffsetMin, C.DateCreated)   AS DateCreated,  -- TZ shifted
				  Left(C.Summary, 255) as Summary,
				  C.Body,
				  Y2.UserID      AS RAuthorID,
				  Y2.DisplayName AS RAuthorName,
				  0 AS NumPosts,
				  F.ForumID AS YForumID,
				  F.oForumID
			FROM      dbo.ActiveForums_Content     C
			JOIN      dbo.ActiveForums_Topics      T ON T.ContentID = C.ContentID
			JOIN      dbo.ActiveForums_ForumTopics X ON T.TopicID   = X.TopicID
			JOIN      dbo.yaf_forum                F ON X.Forumid   = F.oForumID
			JOIN      dbo.Users                   U1 ON C.AuthorID  = U1.UserID
			JOIN      dbo.Yaf_User                Y1 ON U1.UserName = Y1.Name AND Y1.BoardID = @BoardID
			LEFT JOIN dbo.ActiveForums_Replies     R ON R.ReplyID   = X.LastReplyID
			LEFT JOIN dbo.ActiveForums_Content     A ON R.ContentID = A.ContentID
			LEFT JOIN dbo.Users                   U2 ON A.AuthorID  = U2.UserID
			LEFT JOIN dbo.yaf_User                Y2 ON U2.UserName = Y2.Name AND Y2.BoardID = @BoardID
			WHERE C.isDeleted = 0
		  ) S ON T.oTopicID = S.TopicID
	WHEN NOT MATCHED THEN INSERT (   ForumID,     UserID, UserName, UserDisplayName,        Posted,     Topic, Description, Status,   Styles, LinkDate, Views, Priority, PollID, TopicMovedID,      LastPosted, LastMessageID,  LastUserID, LastUserName, LastUserDisplayName,  NumPosts,  Flags, AnswerMessageId, LastMessageFlags, TopicImage, oTopicID)
						  VALUES (S.YForumID, S.AuthorID,     Null,    S.AuthorName, S.DateCreated, S.Subject,   S.Summary, YState,      N'',     Null,     0,        0,   Null,         Null, S.LastReplyDate,          Null, S.RAuthorID,         Null,       S.RAuthorName,         0, YFlags,            Null,              0,       Null,  TopicID);

	/* YAF MessageFlags: IsHtml = 1, IsBBCode = 2, IsSmilies = 4, IsDeleted = 8, IsApproved = 16, IsLocked = 32, NotFormatted = 64, IsReported = 128, IsPersistant = 512 */
	PRINT N'Copy Initial Posts:';
	MERGE INTO dbo.yaf_Message T
	USING (SELECT C.ContentID,
	              512 + 4 -- persistant and smilies allowed
				  + 1 -- containes HTML, else + 2
				  + CASE WHEN R.IsPinned   = 1 THEN    0 ELSE 0 END -- no equivalent?
				  + CASE WHEN R.isDeleted  = 1 THEN    8 ELSE 0 END
				  + CASE WHEN R.IsApproved = 1 THEN   16 ELSE 0 END
				  + CASE WHEN R.IsLocked   = 1 THEN   32 ELSE 0 END AS YFlags,
				  Y.UserID      AS AuthorID,
				  Y.DisplayName AS AuthorName,
				  C.Body,
				  DateAdd(n, @TZOffsetMin, C.DateCreated) AS DateCreated,-- TZ shifted
				  C.IPAddress,
				  T.TopicID
			FROM  dbo.ActiveForums_Topics  R
			JOIN  dbo.ActiveForums_Content C ON R.ContentID  = C.ContentID
			JOIN  dbo.yaf_Topic            T ON R.TopicID    = T.oTopicID
			JOIN  dbo.Users                U ON C.AuthorID   = U.UserID
			JOIN  dbo.yaf_User             Y ON U.UserName   = Y.Name AND Y.BoardID = @BoardID
		  ) S ON T.oContentID = S.ContentID
	WHEN NOT MATCHED THEN INSERT (  TopicID, ReplyTo, Position, Indent,     UserID, UserName, UserDisplayName,        Posted, Message,          IP, Edited,  Flags, EditReason, IsModeratorChanged, DeleteReason, ExternalMessageId, ReferenceMessageId, BlogPostID, EditedBy,  oContentID)
						  VALUES (S.TopicID,    Null,        0,      0, S.AuthorID,     Null,    S.AuthorName, S.DateCreated,  S.Body, S.IPAddress,   Null, YFlags,       Null,                  0,         Null,              Null,               Null,       Null,     Null, S.ContentID);

	PRINT N'Copy Replies:';
	MERGE INTO dbo.yaf_Message T
	USING (SELECT C.ContentID,
	              512 + 4 -- persistant and smilies allowed
				  + 1 -- containes HTML, else + 2
				  + CASE WHEN R.isDeleted  = 1 THEN    8 ELSE 0 END
				  + CASE WHEN R.IsApproved = 1 THEN   16 ELSE 0 END
				  + CASE WHEN X.IsLocked   = 1 THEN   32 ELSE 0 END AS YFlags,
				  Y.UserID      AS AuthorID,
				  Y.DisplayName AS AuthorName,
				  C.Subject,
				  C.Body,
				  DateAdd(n, @TZOffsetMin, C.DateCreated) AS DateCreated,-- TZ shifted
				  C.IPAddress,
				  T.TopicID,
				  M.MessageID
			FROM  dbo.ActiveForums_Replies R
			JOIN  dbo.ActiveForums_Content C ON R.ContentID  = C.ContentID
			JOIN  dbo.ActiveForums_Topics  X ON R.TopicID    = X.TopicID
			JOIN  dbo.yaf_Topic            T ON R.TopicID    = T.oTopicID
			JOIN  dbo.yaf_Message          M ON T.TopicID    = M.TopicID
			JOIN  dbo.Users                U ON C.AuthorID   = U.UserID
			JOIN  dbo.yaf_User             Y ON U.UserName   = Y.Name AND Y.BoardID = @BoardID
		  ) S ON T.oContentID = S.ContentID
	WHEN NOT MATCHED THEN INSERT (  TopicID,     ReplyTo, Position, Indent,     UserID, UserName, UserDisplayName,        Posted, Message,          IP, Edited,  Flags, EditReason, IsModeratorChanged, DeleteReason, ExternalMessageId, ReferenceMessageId, BlogPostID, EditedBy,  oContentID)
						  VALUES (S.TopicID, S.MessageID,        1,      1, S.AuthorID,     Null,    S.AuthorName, S.DateCreated,  S.Body, S.IPAddress,   Null, YFlags,       Null,                  0,         Null,              Null,               Null,       Null,     Null, S.ContentID);

	PRINT N'Copy Attachments:';
	MERGE INTO dbo.yaf_Attachment T
	USING (SELECT A.Filename,
				  A.FileData,
				  A.ContentType,
				  A.FileSize,
				  Y.UserID,
				  M.MessageID
			FROM  dbo.activeforums_Attachments A
			JOIN  dbo.yaf_Message              M ON A.ContentID = M.oContentID
			JOIN  dbo.Users                    U ON A.UserID = U.UserID
			JOIN  dbo.yaf_User                 Y ON U.UserName = Y.Name
		  ) S ON T.FileName = S.FileName AND T.MessageID = S.MessageID
	WHEN NOT MATCHED THEN INSERT (  MessageID,   UserID,   FileName,      Bytes,   ContentType, Downloads, FileData)
						  VALUES (S.MessageID, S.USerID, S.FileName, S.FileSize, S.ContentType,       0, S.FileData);

	PRINT N'Update Thread Statistics:'
	UPDATE T
	 SET   NumPosts         = N,
	       LastMessageID    = MaxID,
		   LastMessageFlags = 534
	FROM dbo.yaf_Topic T
	JOIN (SELECT TopicID, Count(1) N, Max(MessageID) MaxID FROM dbo.yaf_Message GROUP BY TopicID) M ON T.TopicID = M.TopicID
	WHERE NumPosts = 0;

	PRINT N'Copy Forum Subscriptions (yaf_Watch):';
	MERGE INTO dbo.yaf_WatchForum T
	USING (SELECT Y.UserID,
				  N.ForumID,
				  DateAdd(n, @TZOffsetMin, Max(F.LastAccessDate)) AS LastAccessDate -- TZ shifted
			FROM dbo.ActiveForums_Forums_Tracking F
			JOIN dbo.Yaf_Forum                    N On F.ForumID  = N.oForumID
			JOIN dbo.Users                        U On F.UserID   = U.UserID
			JOIN dbo.Yaf_User                     Y on U.UserName = Y.Name AND Y.BoardID = @BoardID
			GROUP BY Y.UserID, N.ForumID
		  ) S ON T.ForumID = S.ForumID and T.UserID = S.UserID
	WHEN NOT MATCHED THEN INSERT (  ForumID,   UserID,          Created,     LastMail)
						  VALUES (S.ForumID, S.UserID, S.LastAccessDate, GetUTCDate());

	PRINT N'Copy Topic Subscriptions (yaf_Watch):';
	MERGE INTO dbo.yaf_WatchTopic T
	USING (SELECT Y.UserID,
				  N.TopicID,
				  DateAdd(n, @TZOffsetMin, Max(F.DateAdded)) AS DateAdded  -- TZ shifted
			FROM dbo.ActiveForums_Topics_Tracking F
			JOIN dbo.Yaf_Topic                    N On F.TopicID  = N.oTopicID
			JOIN dbo.Users                        U On F.UserID   = U.UserID
			JOIN dbo.Yaf_User                     Y on u.UserName = Y.Name AND Y.BoardID = @BoardID
			GROUP BY Y.UserID, N.TopicID
		  ) S ON T.TopicID = S.TopicID and T.UserID = S.UserID
	WHEN NOT MATCHED THEN INSERT (  TopicID,   UserID,     Created,     LastMail)
						  VALUES (S.TopicID, S.UserID, S.DateAdded, GetUTCDate());

	PRINT N'Create Admin Access to Forums:';
	MERGE INTO dbo.yaf_ForumAccess T
	USING (SELECT GroupID, ForumID, M.AccessMaskID
			FROM  dbo.yaf_AccessMask M
			JOIN  dbo.yaf_Group      G ON M.BoardID = G.BoardID AND G.Flags = 1
			JOIN  dbo.yaf_Category   C ON M.BoardID = C.BoardID AND M.Flags = 2047
			JOIN  dbo.yaf_Forum      F ON F.CategoryID = C.CategoryID
			WHERE M.BoardID = @BoardID
		  ) S ON T.ForumID = S.ForumID AND T.GroupID = S.GroupID
	WHEN NOT MATCHED THEN INSERT (  GroupID,   ForumID,   AccessMaskID)
						VALUES (S.GroupID, S.ForumID, S.AccessMaskID);

	-- Copy group & forum permission // skipped due to incompatible Permission format, please set manually
	-- AF Stores each permission for each forum and group as String of format N'0;13;|1134;||'
	-- | is delimiter for main parts:  RoleIDs Granted | UserIDs granted | SocialGroupID Owners granted | ?
	-- each part is a list of id's delimited by ; or :

	Print N'Resynchronize Board Info:';
	Exec dbo.[yaf_forum_resync] @BoardID;

END TRY

BEGIN CATCH
    PRINT N'Error '    + CAST(ERROR_NUMBER() AS nVarChar(11))
	    + N' in Line ' + CAST(ERROR_LINE()   AS nVarChar(11))
		+ N': ' + ERROR_MESSAGE();
	Rollback TRANSACTION
END CATCH;

IF @@TRANCOUNT > 0  BEGIN
 	COMMIT TRANSACTION;
	PRINT N'*** Migration completed ***';
END; -- IF

GO

Print N'Undo temporary modifications of YAF.Net tables...';
IF Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_Message')  AND name = N'oContentID')
  ALTER TABLE dbo.yaf_Message  DROP Column oContentID;

IF Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_Topic')    AND name = N'oTopicID')
  ALTER TABLE dbo.yaf_Topic    DROP Column oTopicID;

IF Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_forum')    AND name = N'oForumID')
  ALTER TABLE dbo.yaf_forum    DROP Column oForumID;

IF Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_category') AND name = N'oGroupID')
  ALTER TABLE dbo.yaf_category DROP Column oGroupID;

IF Exists (SELECT * FROM sys.columns where object_id = OBJECT_ID(N'dbo.yaf_board')    AND name = N'oModuleID')
  ALTER TABLE dbo.yaf_board    DROP Column oModuleID;
GO
Print N'Script finished. Thank you for your patience...'