#import "DecisionSchema.h"
#import <math.h>

NSArray<NSString *> *RCJevAnalysisFieldOrder(void) {
    return @[@"scene", @"intent", @"focus", @"addressee", @"expectation", @"subtext", @"emotion", @"trajectory", @"pressure", @"urgency", @"commitment", @"risk", @"evidence", @"gap"];
}

NSDictionary *RCJevAnalysisSchema(void) {
    static NSDictionary *schema;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        schema = @{
            @"scene": @{ @"title": @"对话情景", @"instructions": @"结合最近话题和更早的相关轮次判断当前交谈主题；不能凭称呼猜测关系。多种场景混合且无主导时选 mixed。", @"options": @{
                @"coordination": @{ @"label": @"工作协作", @"criterion": @"任务分工、汇报、审核、排期或同事合作" },
                @"transaction": @{ @"label": @"交易服务", @"criterion": @"购买、报价、售后、账款、客服或商业谈判" },
                @"relationship": @{ @"label": @"关系沟通", @"criterion": @"明确围绕亲近程度、在乎、信任、陪伴或关系期待" },
                @"daily": @{ @"label": @"日常社交", @"criterion": @"普通闲聊、分享、邀约或生活安排" },
                @"support": @{ @"label": @"情绪倾诉", @"criterion": @"讲述自身压力、困扰或寻求理解" },
                @"dispute": @{ @"label": @"分歧争议", @"criterion": @"围绕事实、责任、立场或边界进行争论" },
                @"information": @{ @"label": @"知识交流", @"criterion": @"信息查询、知识讨论或事实核实" },
                @"safety": @{ @"label": @"安全与求助", @"criterion": @"出现人身危险、紧迫困境或明确求助" },
                @"mixed": @{ @"label": @"混合情景", @"criterion": @"多个主题并行且无主导" },
                @"unknown": @{ @"label": @"情景不明", @"criterion": @"上下文不足以归类" },
            } },
            @"intent": @{ @"title": @"这句话在表达什么", @"instructions": @"判断 target 消息在连续对话中的主要交际作用。问号不等于求知识；反问、短答和玩笑需前文佐证。次要可能性体现在概率分布。", @"options": @{
                @"ask": @{ @"label": @"询问信息", @"criterion": @"主要想获得未知事实或说明" },
                @"request": @{ @"label": @"提出诉求", @"criterion": @"表达希望某事发生或由某人完成" },
                @"check": @{ @"label": @"核对与追问", @"criterion": @"检验前述说法、理解或进展" },
                @"reassurance": @{ @"label": @"寻求确认", @"criterion": @"主要确认被在乎、被理解或关系是否可靠" },
                @"complaint": @{ @"label": @"表达不满", @"criterion": @"对落差、失望或未兑现之事表达异议" },
                @"boundary": @{ @"label": @"表达边界", @"criterion": @"表明接受范围、拒绝、立场或底线" },
                @"share": @{ @"label": @"分享与告知", @"criterion": @"传达近况、事实或体验" },
                @"bond": @{ @"label": @"联络感情", @"criterion": @"问候、亲近、玩笑或维持交流" },
                @"negotiate": @{ @"label": @"协商条件", @"criterion": @"就安排、代价、责任或条件交换立场" },
                @"acknowledge": @{ @"label": @"确认与承接", @"criterion": @"对上一轮表示收到、理解或接受" },
                @"close": @{ @"label": @"结束话题", @"criterion": @"有证据表明正在收束交流" },
                @"other": @{ @"label": @"其他作用", @"criterion": @"可判断但不属于上述类别" },
                @"unknown": @{ @"label": @"意图不明", @"criterion": @"多种解释缺乏区分证据" },
            } },
            @"focus": @{ @"title": @"当前关注点", @"instructions": @"这是对对方正在关注什么的假设，不是建议用户采取行动。依赖其原话、前后对照与重复追问；不要编造潜意识。", @"options": @{
                @"facts": @{ @"label": @"事实与信息", @"criterion": @"关注信息是否准确或解释是否完整" },
                @"care": @{ @"label": @"在乎与理解", @"criterion": @"关注自身感受是否被重视和理解" },
                @"followthrough": @{ @"label": @"兑现与进展", @"criterion": @"关注已谈及事项是否实际发生" },
                @"responsibility": @{ @"label": @"责任与公平", @"criterion": @"关注谁承担责任、投入或结果是否公平" },
                @"certainty": @{ @"label": @"确定性", @"criterion": @"关注时间、条件、承诺是否清楚可靠" },
                @"autonomy": @{ @"label": @"边界与自主", @"criterion": @"关注选择权、接受范围或不被强迫" },
                @"connection": @{ @"label": @"联系与陪伴", @"criterion": @"关注是否保持交流和连接" },
                @"closure": @{ @"label": @"话题收束", @"criterion": @"关注当前讨论是否可以结束" },
                @"none": @{ @"label": @"无明显焦点", @"criterion": @"普通交流，无额外关注点证据" },
                @"unknown": @{ @"label": @"关注点不明", @"criterion": @"缺少足够上下文支持" },
            } },
            @"addressee": @{ @"title": @"消息指向", @"instructions": @"区分目标消息是在对用户本人、另一位成员还是整个群体说话。群中连续发言不能自动归因给用户；不明确时选 unknown。单聊通常为 user，但转述不代表对用户提出要求。", @"options": @{
                @"user": @{ @"label": @"指向我", @"criterion": @"单聊直接对话或群聊有明确点名、承接用户的证据" },
                @"group": @{ @"label": @"面向全体", @"criterion": @"向群体公告、征询或提问" },
                @"other": @{ @"label": @"指向他人", @"criterion": @"承接另一成员或明确点名别人" },
                @"unknown": @{ @"label": @"指向不明", @"criterion": @"群聊交叉对话或证据不足" },
            } },
            @"expectation": @{ @"title": @"对方是否在等待回应", @"instructions": @"只判断对方表现出来的回应期待，不决定用户应该回什么或是否回复。不把所有提问或群公告都视作要求用户回应。", @"options": @{
                @"explicit": @{ @"label": @"明确等待回应", @"criterion": @"文字明确要求回答、确认或反馈" },
                @"implicit": @{ @"label": @"可能期待回应", @"criterion": @"上下文体现一个未完成的问答或确认轮次" },
                @"open": @{ @"label": @"可回应但无明显要求", @"criterion": @"分享或闲聊且没有明显回应压力" },
                @"closed": @{ @"label": @"暂未表现回应期待", @"criterion": @"明确收束或说明无需回应" },
                @"elsewhere": @{ @"label": @"回应对象是他人", @"criterion": @"主要在等另一位参与者的回应" },
                @"unknown": @{ @"label": @"回应期待不明", @"criterion": @"不足以区分" },
            } },
            @"subtext": @{ @"title": @"字面与语境", @"instructions": @"只评估语义是否超出字面。隐含诉求须有可见上下文，不能只因关系亲近就认定试探、反话或生气。", @"options": @{
                @"literal": @{ @"label": @"以字面含义为主", @"criterion": @"字面解释与前后文一致" },
                @"implicit": @{ @"label": @"存在间接表达", @"criterion": @"前后文支持字面问题承载额外诉求" },
                @"ironic": @{ @"label": @"可能反问或反讽", @"criterion": @"有明确语境矛盾或反问信号" },
                @"playful": @{ @"label": @"可能玩笑或调侃", @"criterion": @"可见互动支持非严肃表达" },
                @"ambiguous": @{ @"label": @"多种解读并存", @"criterion": @"字面与非字面均有可能" },
                @"unknown": @{ @"label": @"缺少判断依据", @"criterion": @"关键前文、语音或表情不可见" },
            } },
            @"emotion": @{ @"title": @"可见情绪线索", @"instructions": @"描述该消息与最近轮次传达的语气线索，不诊断心理状态。短句、标点或沉默本身不能证明愤怒；不将玩笑自动当攻击。", @"options": @{
                @"neutral": @{ @"label": @"平静中性", @"criterion": @"未见明显正负情绪" },
                @"warm": @{ @"label": @"友好亲近", @"criterion": @"有温暖、肯定或亲近表达" },
                @"curious": @{ @"label": @"好奇关切", @"criterion": @"有探询、关注或关心" },
                @"disappointed": @{ @"label": @"失望失落", @"criterion": @"表达期待落空或不被重视" },
                @"anxious": @{ @"label": @"担心不安", @"criterion": @"表达不确定、担忧或紧张" },
                @"frustrated": @{ @"label": @"不满烦躁", @"criterion": @"有明确不耐烦、抱怨或反复受阻" },
                @"angry": @{ @"label": @"明显愤怒", @"criterion": @"直接强烈责备或愤怒表达" },
                @"hurt": @{ @"label": @"委屈受伤", @"criterion": @"明确表达被伤害、被忽视或委屈" },
                @"playful": @{ @"label": @"轻松调侃", @"criterion": @"有玩笑语境" },
                @"mixed": @{ @"label": @"情绪混合", @"criterion": @"多种情绪同时存在" },
                @"unknown": @{ @"label": @"线索不足", @"criterion": @"不能可靠区分" },
            } },
            @"trajectory": @{ @"title": @"对话正在怎样变化", @"instructions": @"比较 target 前后相邻轮次和更早相关轮次。只用 target 及之前记录，判断局势变化；没有对照时选 unknown。简短肯定不等于问题已解决。", @"options": @{
                @"stable": @{ @"label": @"基本平稳", @"criterion": @"相比前文无明显变化" },
                @"warming": @{ @"label": @"互动升温", @"criterion": @"交流投入或亲近程度增加" },
                @"easing": @{ @"label": @"紧张缓和", @"criterion": @"此前紧张在文字中出现缓解证据" },
                @"escalating": @{ @"label": @"分歧升级", @"criterion": @"责备、对立或压力较前文增强" },
                @"stalled": @{ @"label": @"问题停滞", @"criterion": @"同一未解焦点持续循环" },
                @"closing": @{ @"label": @"趋于收束", @"criterion": @"话题明确走向结束" },
                @"shift": @{ @"label": @"话题转移", @"criterion": @"主要讨论对象发生改变" },
                @"unknown": @{ @"label": @"趋势不明", @"criterion": @"缺少可比较的轮次或混杂" },
            } },
            @"pressure": @{ @"title": @"沟通压力", @"instructions": @"评估可见的催促、质疑、对立或施压程度，不等同危险评分，也不按亲密关系模板臆测危机。", @"options": @{
                @"none": @{ @"label": @"未见压力", @"criterion": @"未见催促或对立" },
                @"low": @{ @"label": @"轻度压力", @"criterion": @"轻微追问、犹豫或期待落差" },
                @"medium": @{ @"label": @"明显压力", @"criterion": @"重复催促、明确质疑或未解分歧" },
                @"high": @{ @"label": @"强烈压力", @"criterion": @"持续强迫、强烈冲突或明确威胁" },
                @"unknown": @{ @"label": @"压力不明", @"criterion": @"缺少必要信息" },
            } },
            @"urgency": @{ @"title": @"时间紧迫性", @"instructions": @"只判断消息中明确或有证据支持的时间要求。消息时间间隔不等于对方催促，不建议行动。", @"options": @{
                @"immediate": @{ @"label": @"明确即时要求", @"criterion": @"明确要求现在处理或紧迫时限" },
                @"bounded": @{ @"label": @"有明确期限", @"criterion": @"提及具体截止时间或约定时间" },
                @"flexible": @{ @"label": @"时间较灵活", @"criterion": @"明确表示不急或时间可商量" },
                @"unspecified": @{ @"label": @"未说明时限", @"criterion": @"没有时间要求" },
                @"unknown": @{ @"label": @"时间信息不完整", @"criterion": @"依赖未展示的安排" },
            } },
            @"commitment": @{ @"title": @"约定处于什么状态", @"instructions": @"追踪与 target 相关的承诺或安排。区分想法、提议、双方确认和已完成；不因一方口头答应就认定已执行。", @"options": @{
                @"none": @{ @"label": @"未涉及约定", @"criterion": @"没有相关承诺或安排" },
                @"proposed": @{ @"label": @"尚在提出或协商", @"criterion": @"提出想法或条件但未共同确认" },
                @"agreed": @{ @"label": @"已有明确约定", @"criterion": @"可见双方确认具体事项" },
                @"pending": @{ @"label": @"约定尚待兑现", @"criterion": @"讨论焦点是尚未完成的约定" },
                @"disputed": @{ @"label": @"约定存在分歧", @"criterion": @"对内容、责任或是否答应有争议" },
                @"fulfilled": @{ @"label": @"有完成证据", @"criterion": @"可见明确完成确认" },
                @"unknown": @{ @"label": @"约定状态不明", @"criterion": @"引用旧事但原始约定不可见" },
            } },
            @"risk": @{ @"title": @"内容涉及的敏感领域", @"instructions": @"仅分类当前内容涉及什么敏感议题，不输出医疗、法律、财务或处事建议；不把普通分歧等同人身危险。多种风险时选最明确且后果重的一项。", @"options": @{
                @"ordinary": @{ @"label": @"普通交流", @"criterion": @"未见显著敏感议题" },
                @"relationship": @{ @"label": @"关系与信任", @"criterion": @"明确涉及重要关系、信任或情感边界" },
                @"privacy": @{ @"label": @"隐私与信息", @"criterion": @"个人秘密、账号或敏感身份资料" },
                @"money": @{ @"label": @"金钱与交易", @"criterion": @"款项、交易或财务损失" },
                @"health": @{ @"label": @"健康议题", @"criterion": @"医疗或健康问题" },
                @"legal": @{ @"label": @"权责与法律", @"criterion": @"合同、法律权利或责任" },
                @"safety": @{ @"label": @"人身安全", @"criterion": @"具体威胁、自伤或他伤线索" },
                @"unknown": @{ @"label": @"领域不明", @"criterion": @"关键内容未展示" },
            } },
            @"evidence": @{ @"title": @"判断依据充分吗", @"instructions": @"审视可见记录对本次 target 判断的支撑力度，而非评估用户诚实。只读到一条短句、媒体缺失、指代不明、旧事未展示时应降低充分性。", @"options": @{
                @"explicit": @{ @"label": @"有直接文字依据", @"criterion": @"当前或相关历史明确说出了诉求或事实" },
                @"contextual": @{ @"label": @"依赖连续对话", @"criterion": @"需结合多轮但相关记录完整且相互支持" },
                @"mixed": @{ @"label": @"证据存在冲突", @"criterion": @"不同轮次或不同发言者的信息互相矛盾" },
                @"thin": @{ @"label": @"只能弱推测", @"criterion": @"记录短少或解释分歧大" },
                @"missing": @{ @"label": @"关键上下文缺失", @"criterion": @"关键媒体、指代对象、约定或历史不可见" },
            } },
            @"gap": @{ @"title": @"主要信息缺口", @"instructions": @"识别最影响理解 target 的缺口；不要把未知信息补写成事实。已经具备必要信息时选 none。", @"options": @{
                @"none": @{ @"label": @"未见关键缺口", @"criterion": @"当前可见文字足以理解主要事项" },
                @"history": @{ @"label": @"此前经过缺失", @"criterion": @"提及此前事件但未展示" },
                @"referent": @{ @"label": @"指代对象不清", @"criterion": @"这件事、那个人、引用对象无法定位" },
                @"media": @{ @"label": @"媒体内容不可见", @"criterion": @"依赖语音、图片、视频或未读取引用" },
                @"recipient": @{ @"label": @"群聊对象不明", @"criterion": @"无法确定是在对谁说话" },
                @"facts": @{ @"label": @"关键事实未确认", @"criterion": @"事项真假、约定或条件尚未确认" },
                @"tone": @{ @"label": @"语气解释不唯一", @"criterion": @"玩笑、反话或情绪存在多种解读" },
                @"other": @{ @"label": @"其他缺口", @"criterion": @"可见其他未覆盖缺口" },
            } },
        };
    });
    return schema;
}

NSString *RCFormatJevAnalysis(RCDecisionResult *decision) {
    NSDictionary *schema = RCJevAnalysisSchema();
    if (decision.schemaVersion != 2 || !decision.judgments.count) return @"JEV · 判断结果不可用";
    NSString *(^label)(NSString *) = ^NSString *(NSString *field) {
        return schema[field][@"options"][decision.judgments[field]][@"label"] ?: @"信息不足";
    };
    NSMutableArray *lines = [NSMutableArray arrayWithObjects:@"JEV · 情景判断",
        [NSString stringWithFormat:@"判断：%@%@ · %@",
            [decision.confidence[@"focus"] doubleValue] < 0.55 ||
            [decision.confidence[@"trajectory"] doubleValue] < 0.55 ||
            [decision.judgments[@"evidence"] isEqualToString:@"thin"] ||
            [decision.judgments[@"evidence"] isEqualToString:@"missing"] ? @"待确认 · " : @"",
            label(@"focus"), label(@"trajectory")],
        [NSString stringWithFormat:@"依据范围：%lu 条可见记录%@", (unsigned long)decision.contextMessageCount,
            decision.contextPartial ? @"（有截断或缺失）" : @"（不含未加载历史）"],
        @"以下为模型选项分布，不代表已确认的真实动机。", nil];
    for (NSString *field in RCJevAnalysisFieldOrder()) {
        NSDictionary *probabilities = decision.probabilities[field];
        NSArray *ranked = [probabilities.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSComparisonResult order = [probabilities[b] compare:probabilities[a]];
            return order == NSOrderedSame ? [a compare:b] : order;
        }];
        NSString *choice = decision.judgments[field];
        NSMutableArray *parts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@ %.0f%%",
            label(field), [probabilities[choice] doubleValue] * 100]];
        for (NSString *alternative in ranked) {
            if ([alternative isEqualToString:choice] || [probabilities[alternative] doubleValue] < 0.15) continue;
            [parts addObject:[NSString stringWithFormat:@"%@ %.0f%%",
                schema[field][@"options"][alternative][@"label"], [probabilities[alternative] doubleValue] * 100]];
            break;
        }
        NSString *uncertain = [decision.confidence[field] doubleValue] < 0.55 ? @"〔低置信〕" : @"";
        [lines addObject:[NSString stringWithFormat:@"%@：%@%@", schema[field][@"title"],
            [parts componentsJoinedByString:@" / "], uncertain]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

NSString *RCJevAnalysisPreview(NSString *text) {
    for (NSString *line in [text componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:@"判断："]) return [@"JEV：" stringByAppendingString:[line substringFromIndex:3]];
    return @"JEV · 旧版分析记录";
}

NSString *RCDisplayStoredAnalysis(NSString *text) {
    if ([text hasPrefix:@"JEV · 情景判断"]) return text;
    // Keep old records on disk, while removing their obsolete reply advice.
    NSMutableArray *lines = [NSMutableArray arrayWithObject:@"JEV · 旧版分析记录"];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange intent = [line rangeOfString:@"意图："];
        NSRange risk = [line rangeOfString:@"风险："];
        if (intent.location != NSNotFound) [lines addObject:[line substringFromIndex:intent.location]];
        if (risk.location != NSNotFound) [lines addObject:[line substringFromIndex:risk.location]];
    }
    [lines addObject:@"此记录没有新版情景维度，重新分析后更新。"];
    return [lines componentsJoinedByString:@"\n"];
}
