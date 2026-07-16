# 我需要在提交到后端前，给新创建的块创建一个orderKey。

## key的创建分为两种情况，
1. **一种是笔记已经创建，提交已有修改的内容**：利用`NoteDocumentConvert.generateOrderKey(preKey,afterKey)`来创建key。需要传入参数preKey和afterKey。
2. **另一种是，笔记还没有创建，本次flush刚刚创建了Note**：那么此时就可以利用`_orderKeyForIndex`给所有的块分配orderKey


我现在有个需求：我有一个方法是给一个节点分配一个orderKey，分配的函数需要知道当前节点的前一个节点的OrderKey和后一个节点的OrderKey。现在有一个情况，就是比如我有五个节点如下，如何设计一个算法给所有为null的几点分配一个符合顺序的orderKey：
| 块索引 | 块的OrderKey |
| :--- | :--- |
| 0 | a |
| 1 | null | 
| 2 | null | 
| 3 | null | 
| 4 | b | 